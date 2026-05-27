#!/bin/bash

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== VPN Shop Backend Installer (With Sync & Reset Logic + Backup/Restore) ===${NC}"

# 1. Check Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit
fi

# 2. Update System & Install Dependencies
echo -e "${YELLOW}Updating System...${NC}"
apt update && apt upgrade -y
apt install -y curl wget gnupg2 ca-certificates lsb-release nginx git

# 3. Install Node.js 18
echo -e "${YELLOW}Installing Node.js...${NC}"
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# 4. Setup Directory Structure
echo -e "${YELLOW}Setting up directories...${NC}"
mkdir -p /root/vpn-shop

# 5. Stop existing process if running
if command -v pm2 &> /dev/null; then
    pm2 stop vpn-shop 2>/dev/null
    pm2 delete vpn-shop 2>/dev/null
fi

# 6. Create backend files (bot.js) with RESET & TOP UP Logic + API + BACKUP SYSTEM
echo -e "${YELLOW}Creating Backend Files (Synced & Backup Logic)...${NC}"
cat << 'EOF' > /root/vpn-shop/bot.js
const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const TelegramBot = require('node-telegram-bot-api');
const axios = require('axios');
const https = require('https');
const fs = require('fs');
const moment = require('moment-timezone');
const { exec } = require('child_process');

const app = express();
app.use(cors());
app.use(bodyParser.json());

const CONFIG_FILE = 'config.json';
const CLAIM_FILE = 'claimed_users.json';
const BLOCKED_FILE = 'blocked_registry.json';
const RESELLER_FILE = 'resellers.json';
const ALL_USERS_FILE = 'all_users.json';
const OFFSET_FILE = 'usage_offsets.json'; // *** NEW: Reset Database ***

let config = {};
let bot = null;
let claimedUsers = [];
let blockedRegistry = {}; 
let userStates = {};
let resellers = [];
let resellerSessions = {}; 
let allUsers = []; 
let usageOffsets = {}; // *** NEW: Memory Cache ***

let isGuardianRunning = false;

const agent = new https.Agent({ rejectUnauthorized: false });
const axiosClient = axios.create({ httpsAgent: agent, timeout: 10000, headers: { 'Content-Type': 'application/json' } });

function loadConfig() {
    try { if(fs.existsSync(CONFIG_FILE)) config = JSON.parse(fs.readFileSync(CONFIG_FILE)); } catch (e) {}
    try { if(fs.existsSync(CLAIM_FILE)) claimedUsers = JSON.parse(fs.readFileSync(CLAIM_FILE)); } catch(e) {}
    try { if(fs.existsSync(BLOCKED_FILE)) blockedRegistry = JSON.parse(fs.readFileSync(BLOCKED_FILE)); } catch(e) {}
    try { if(fs.existsSync(RESELLER_FILE)) resellers = JSON.parse(fs.readFileSync(RESELLER_FILE)); } catch(e) {}
    try { if(fs.existsSync(ALL_USERS_FILE)) allUsers = JSON.parse(fs.readFileSync(ALL_USERS_FILE)); } catch(e) {}
    try { if(fs.existsSync(OFFSET_FILE)) usageOffsets = JSON.parse(fs.readFileSync(OFFSET_FILE)); } catch(e) {}
}
loadConfig();

// *** CRITICAL: SAVE OFFSET FUNCTION ***
function saveOffsets() {
    try { fs.writeFileSync(OFFSET_FILE, JSON.stringify(usageOffsets, null, 4)); } catch(e) {}
}

// --- API ROUTES FOR SYNC ---
app.get('/api/offsets', (req, res) => {
    try { if(fs.existsSync(OFFSET_FILE)) usageOffsets = JSON.parse(fs.readFileSync(OFFSET_FILE)); } catch(e) {}
    res.json(usageOffsets);
});

app.post('/api/set-offset', (req, res) => {
    const { keyId, offset } = req.body;
    if (keyId) {
        usageOffsets[keyId] = parseInt(offset) || 0;
        saveOffsets();
        res.json({ success: true });
    } else {
        res.status(400).json({ error: "Missing keyId" });
    }
});

app.get('/api/config', (req, res) => { loadConfig(); res.json({ ...config, resellers }); });

app.post('/api/update-config', (req, res) => {
    try {
        const { resellers: newResellers, ...newConfig } = req.body;
        config = { ...config, ...newConfig };
        fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 4));
        if(newResellers) { resellers = newResellers; fs.writeFileSync(RESELLER_FILE, JSON.stringify(resellers, null, 4)); }
        res.json({ success: true, config: config });
        setTimeout(() => { loadConfig(); startBot(); }, 1000);
    } catch (error) { res.status(500).json({ success: false }); }
});

app.post('/api/change-port', (req, res) => {
    const newPort = req.body.port;
    if(!newPort || isNaN(newPort)) return res.status(400).json({error: "Invalid Port"});
    const nginxConfig = `server { listen ${newPort}; server_name _; root /var/www/html; index index.html; location / { try_files $uri $uri/ =404; } }`;
    try { fs.writeFileSync('/etc/nginx/sites-available/default', nginxConfig); config.panel_port = parseInt(newPort); fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 4)); exec('systemctl reload nginx', (error) => { if (error) { return res.status(500).json({error: "Failed to reload Nginx"}); } res.json({ success: true, message: `Port changed to ${newPort}` }); }); } catch (err) { res.status(500).json({ error: "Failed to write config" }); }
});
app.listen(3000, () => console.log('✅ Sync Server running on Port 3000'));

// --- BOT HELPER FUNCTIONS ---
function getServers() {
    if (!config.api_urls) return [];
    return config.api_urls.map(s => {
        if (typeof s === 'string') return { name: "Server", url: s };
        return s;
    });
}

function getServerKeyboard(callbackPrefix) {
    const servers = getServers();
    let keyboard = [];
    let row = [];
    servers.forEach((srv, index) => {
        let sName = srv.name || `Server ${index + 1}`;
        row.push({ text: `🖥️ ${sName}`, callback_data: `${callbackPrefix}_${index}` });
        if (row.length === 2) {
            keyboard.push(row);
            row = [];
        }
    });
    if (row.length > 0) keyboard.push(row);
    return keyboard;
}

// *** DISPLAY DATA LOGIC (Raw - Offset) ***
function getDisplayData(keyId, rawUsage, rawLimit) {
    let offset = usageOffsets[keyId] || 0;
    
    // Safety check: If server reset (rawUsage < offset), reset offset to 0
    if (rawUsage < offset) {
        offset = 0;
        usageOffsets[keyId] = 0;
        saveOffsets();
    }

    const displayUsed = Math.max(0, rawUsage - offset);
    
    let displayLimit = 0;
    if (rawLimit > 0) {
        displayLimit = Math.max(0, rawLimit - offset);
    }

    return { displayUsed, displayLimit, offset };
}

async function findKeyInAllServers(keyIdOrName, isName = false) {
    const servers = getServers();
    for (const srv of servers) {
        try {
            const serverUrl = srv.url;
            const [kRes, mRes] = await Promise.all([
                axiosClient.get(`${serverUrl}/access-keys`),
                axiosClient.get(`${serverUrl}/metrics/transfer`)
            ]);
            let key;
            if (isName) {
                key = kRes.data.accessKeys.find(k => k.name.includes(keyIdOrName));
            } else {
                key = kRes.data.accessKeys.find(k => String(k.id) === String(keyIdOrName));
            }
            if (key) {
                return { key, metrics: mRes.data, serverUrl, serverName: srv.name };
            }
        } catch (e) { console.error(`Error checking server ${srv.url}:`, e.message); }
    }
    return null;
}

async function getAllKeysFromAllServers(filter = null) {
    const servers = getServers();
    let allKeys = [];
    for (const srv of servers) {
        try {
            const res = await axiosClient.get(`${srv.url}/access-keys`);
            let keys = res.data.accessKeys;
            if(filter) keys = keys.filter(filter);
            keys = keys.map(k => ({ ...k, _serverUrl: srv.url, _serverName: srv.name }));
            allKeys = allKeys.concat(keys);
        } catch (e) {}
    }
    return allKeys;
}

async function getKeysFromSpecificServer(index) {
    const servers = getServers();
    if (!servers[index]) return [];
    const srv = servers[index];
    try {
        const res = await axiosClient.get(`${srv.url}/access-keys`);
        return res.data.accessKeys.map(k => ({ ...k, _serverUrl: srv.url, _serverName: srv.name }));
    } catch (e) { return []; }
}

async function createKeyOnServer(serverIndex, name, limitBytes) {
    const servers = getServers();
    if (!servers[serverIndex]) throw new Error("Invalid Server Index");
    const targetServer = servers[serverIndex];
    const res = await axiosClient.post(`${targetServer.url}/access-keys`);
    await axiosClient.put(`${targetServer.url}/access-keys/${res.data.id}/name`, { name: name });
    await axiosClient.put(`${targetServer.url}/access-keys/${res.data.id}/data-limit`, { limit: { bytes: limitBytes } });
    
    // *** NEW KEY: Init Offset 0 ***
    usageOffsets[res.data.id] = 0;
    saveOffsets();

    return { ...res.data, _serverUrl: targetServer.url, _serverName: targetServer.name };
}

if (config.bot_token && config.api_urls && config.api_urls.length > 0) startBot();

function startBot() {
    if(bot) { try { bot.stopPolling(); } catch(e){} }
    if(!config.bot_token) return;

    console.log("🚀 Starting Bot...");
    bot = new TelegramBot(config.bot_token, { polling: true });
    
    const ADMIN_IDS = config.admin_id ? config.admin_id.split(',').map(id => id.trim()) : [];
    const WELCOME_MSG = config.welcome_msg || "👋 Welcome to VPN Shop!";
    const TRIAL_ENABLED = config.trial_enabled !== false;
    const TRIAL_DAYS = parseInt(config.trial_days) || 1;
    const TRIAL_GB = parseFloat(config.trial_gb) || 1;
    
    const BTN = {
        trial: (config.buttons && config.buttons.trial) ? config.buttons.trial : "🆓 Free Trial",
        buy: (config.buttons && config.buttons.buy) ? config.buttons.buy : "🛒 Buy Key",
        mykey: (config.buttons && config.buttons.mykey) ? config.buttons.mykey : "🔑 My Key",
        info: (config.buttons && config.buttons.info) ? config.buttons.info : "👤 Account Info",
        support: (config.buttons && config.buttons.support) ? config.buttons.support : "🆘 Support",
        reseller: (config.buttons && config.buttons.reseller) ? config.buttons.reseller : "🤝 Reseller Login",
        resell_buy: (config.buttons && config.buttons.resell_buy) ? config.buttons.resell_buy : "🛒 Buy Stock",
        resell_create: (config.buttons && config.buttons.resell_create) ? config.buttons.resell_create : "📦 Create User Key",
        resell_users: (config.buttons && config.buttons.resell_users) ? config.buttons.resell_users : "👥 My Users",
        resell_extend: (config.buttons && config.buttons.resell_extend) ? config.buttons.resell_extend : "⏳ Extend User",
        resell_logout: (config.buttons && config.buttons.resell_logout) ? config.buttons.resell_logout : "🔙 Logout Reseller"
    };

    function formatAccessUrl(url, serverUrl) {
        if (!url) return url;
        try {
            const urlObj = new URL(url);
            const originalIp = urlObj.hostname;
            if (config.domain_map && config.domain_map.length > 0) {
                const mapping = config.domain_map.find(m => m.ip === originalIp);
                if (mapping && mapping.domain) return url.replace(originalIp, mapping.domain);
            }
            if (config.domain) return url.replace(originalIp, config.domain);
            return url;
        } catch (e) { return url; }
    }
    
    function isAdmin(chatId) { return ADMIN_IDS.includes(String(chatId)); }
    function formatBytes(bytes) { if (!bytes || bytes === 0) return '0 B'; const i = Math.floor(Math.log(bytes) / Math.log(1024)); return (bytes / Math.pow(1024, i)).toFixed(2) + ' ' + ['B', 'KB', 'MB', 'GB', 'TB'][i]; }
    function getMyanmarDate(offsetDays = 0) { return moment().tz("Asia/Yangon").add(offsetDays, 'days').format('YYYY-MM-DD'); }
    function isExpired(dateString) { if (!/^\d{4}-\d{2}-\d{2}$/.test(dateString)) return false; const today = moment().tz("Asia/Yangon").startOf('day'); const expire = moment.tz(dateString, "YYYY-MM-DD", "Asia/Yangon").startOf('day'); return expire.isBefore(today); }
    function getDaysRemaining(dateString) { if (!/^\d{4}-\d{2}-\d{2}$/.test(dateString)) return "Unknown"; const today = moment().tz("Asia/Yangon").startOf('day'); const expire = moment.tz(dateString, "YYYY-MM-DD", "Asia/Yangon").startOf('day'); const diff = expire.diff(today, 'days'); return diff >= 0 ? `${diff} Days` : "Expired"; }
    function sanitizeText(text) { if (!text) return ''; return text.replace(/([_*\[\]()~`>#+\-=|{}.!])/g, '\\$1'); }

    function getMainMenu(userId) {
        let kb = []; let row1 = [];
        if (TRIAL_ENABLED) row1.push({ text: BTN.trial });
        row1.push({ text: BTN.buy }); kb.push(row1);
        kb.push([{ text: BTN.mykey }, { text: BTN.info }]); 
        kb.push([{ text: BTN.reseller }, { text: BTN.support }]);
        if (isAdmin(userId)) kb.unshift([{ text: "👮‍♂️ Admin Panel" }]);
        return kb;
    }

    function getResellerMenu(username, balance) {
        return [
            [{ text: `${BTN.resell_buy} (${balance} Ks)` }],
            [{ text: BTN.resell_create }, { text: BTN.resell_extend }],
            [{ text: BTN.resell_users }, { text: BTN.resell_logout }]
        ];
    }

    bot.onText(/\/start/, (msg) => { 
        const userId = msg.chat.id;
        if (!allUsers.includes(userId)) {
            allUsers.push(userId);
            try { fs.writeFileSync(ALL_USERS_FILE, JSON.stringify(allUsers)); } catch(e){}
        }
        delete userStates[userId];
        delete resellerSessions[userId];
        bot.sendMessage(userId, WELCOME_MSG, { reply_markup: { keyboard: getMainMenu(userId), resize_keyboard: true } }); 
    });

    bot.on('message', async (msg) => {
        const chatId = msg.chat.id;
        const text = msg.text;
        
        if (!text) return; 

        if (userStates[chatId]) {
            const state = userStates[chatId];
            
            if (state.status === 'ADMIN_BROADCAST_MSG') {
                if(!isAdmin(chatId)) return;
                const msgText = text;
                bot.sendMessage(chatId, `🚀 **Broadcasting to ${allUsers.length} users...**`, { parse_mode: 'Markdown' });
                let successCount = 0; let failCount = 0;
                for (const uid of allUsers) {
                    try {
                        await bot.sendMessage(uid, `📢 **ANNOUNCEMENT**\n\n${msgText}`, { parse_mode: 'Markdown' });
                        successCount++;
                    } catch (e) { failCount++; }
                    await new Promise(r => setTimeout(r, 50)); 
                }
                bot.sendMessage(chatId, `✅ **Broadcast Completed**\n\n✅ Success: ${successCount}\n❌ Failed/Blocked: ${failCount}`, { 
                    reply_markup: { keyboard: getMainMenu(chatId), resize_keyboard: true } 
                });
                delete userStates[chatId];
                return;
            }

            if (state.status === 'RESELLER_LOGIN_USER') {
                userStates[chatId].username = text.trim();
                userStates[chatId].status = 'RESELLER_LOGIN_PASS';
                return bot.sendMessage(chatId, "🔑 Enter **Password**:", { parse_mode: 'Markdown' });
            }
            if (state.status === 'RESELLER_LOGIN_PASS') {
                const username = userStates[chatId].username;
                const password = text.trim();
                const reseller = resellers.find(r => r.username === username && r.password === password);
                if(reseller) {
                    resellerSessions[chatId] = reseller.username;
                    delete userStates[chatId];
                    bot.sendMessage(chatId, `✅ **Login Success!**\n👤 Owner: ${reseller.username}\n💰 Balance: ${reseller.balance} Ks`, { parse_mode: 'Markdown', reply_markup: { keyboard: getResellerMenu(reseller.username, reseller.balance), resize_keyboard: true } });
                } else {
                    delete userStates[chatId];
                    bot.sendMessage(chatId, "❌ **Login Failed!**", { reply_markup: { keyboard: getMainMenu(chatId), resize_keyboard: true } });
                }
                return;
            }
            
            if (state.status === 'RESELLER_ENTER_NAME') {
                 const { plan, reseller: rUsername, serverIndex } = userStates[chatId];
                 const customerName = text.trim().replace(/\|/g, '');
                 
                 bot.sendMessage(chatId, "⏳ Generating Key...");
                 try {
                    const rIndex = resellers.findIndex(r => r.username === rUsername);
                    if(rIndex === -1 || resellers[rIndex].balance < plan.price) {
                         bot.sendMessage(chatId, "❌ Insufficient Balance or Error.", { reply_markup: { keyboard: getResellerMenu(rUsername, resellers[rIndex] ? resellers[rIndex].balance : 0), resize_keyboard: true } });
                    } else {
                        resellers[rIndex].balance -= parseInt(plan.price);
                        fs.writeFileSync(RESELLER_FILE, JSON.stringify(resellers, null, 4));
                        const expireDate = getMyanmarDate(plan.days);
                        const limitBytes = Math.floor(plan.gb * 1024 * 1024 * 1024);
                        const finalName = `${customerName} (R-${rUsername}) | ${expireDate}`;
                        const data = await createKeyOnServer(serverIndex, finalName, limitBytes);
                        let finalUrl = formatAccessUrl(data.accessUrl, data._serverUrl); finalUrl += `#${encodeURIComponent(customerName)}`;
                        bot.sendMessage(chatId, `✅ **Key Created!**\n\n👤 Customer: ${customerName}\n🖥️ Server: ${data._serverName}\n💰 Cost: ${plan.price} Ks\n💰 Remaining: ${resellers[rIndex].balance} Ks\n\n🔗 **Key:**\n<code>${finalUrl}</code>`, { 
                            parse_mode: 'HTML',
                            reply_markup: { keyboard: getResellerMenu(rUsername, resellers[rIndex].balance), resize_keyboard: true }
                        });
                    }
                 } catch(e) { 
                     bot.sendMessage(chatId, "❌ Error connecting to servers.", { reply_markup: { keyboard: getResellerMenu(rUsername, resellers.find(r=>r.username===rUsername).balance), resize_keyboard: true } }); 
                 }
                 delete userStates[chatId];
                 return;
            }

            if (state.status === 'ADMIN_TOPUP_AMOUNT') {
                if(!isAdmin(chatId)) return;
                const amount = parseInt(text.trim());
                if(isNaN(amount)) return bot.sendMessage(chatId, "❌ Invalid Amount. Enter number only.");
                
                const targetReseller = state.targetReseller;
                const rIndex = resellers.findIndex(r => r.username === targetReseller);
                
                if(rIndex !== -1) {
                    resellers[rIndex].balance = parseInt(resellers[rIndex].balance) + amount;
                    fs.writeFileSync(RESELLER_FILE, JSON.stringify(resellers, null, 4));
                    bot.sendMessage(chatId, `✅ **Topup Success!**\n👤 Reseller: ${targetReseller}\n💰 Added: ${amount} Ks\n💰 New Balance: ${resellers[rIndex].balance} Ks`, { 
                        parse_mode: 'Markdown',
                        reply_markup: { keyboard: getMainMenu(chatId), resize_keyboard: true }
                    });
                } else {
                    bot.sendMessage(chatId, "❌ Reseller not found.", { reply_markup: { keyboard: getMainMenu(chatId), resize_keyboard: true } });
                }
                delete userStates[chatId];
                return;
            }
            return; 
        }

        if (resellerSessions[chatId]) {
            const rUser = resellerSessions[chatId];
            const reseller = resellers.find(r => r.username === rUser);
            
            if (text === BTN.resell_logout) {
                delete resellerSessions[chatId];
                return bot.sendMessage(chatId, "👋 Logged out.", { reply_markup: { keyboard: getMainMenu(chatId), resize_keyboard: true } });
            }
            if (text.startsWith(BTN.resell_buy.split('(')[0].trim())) {
                 return bot.sendMessage(chatId, `💰 **Your Balance:** ${reseller.balance} Ks\n\nTo topup, contact Admin.`, { parse_mode: 'Markdown' });
            }
            if (text === BTN.resell_create) {
                const plansToUse = (config.reseller_plans && config.reseller_plans.length > 0) ? config.reseller_plans : config.plans;
                if(!plansToUse || plansToUse.length === 0) return bot.sendMessage(chatId, "❌ No reseller plans available.");
                const keyboard = plansToUse.map((p, i) => [{ text: `${p.days} Days - ${p.gb}GB - ${p.price}Ks`, callback_data: `resell_buy_${i}` }]); 
                return bot.sendMessage(chatId, "📅 **Choose Reseller Plan:**", { parse_mode: 'Markdown', reply_markup: { inline_keyboard: keyboard } });
            }
            
            if (text === BTN.resell_extend) {
                bot.sendMessage(chatId, "🔎 Loading your users for extension...");
                try {
                    const myKeys = await getAllKeysFromAllServers(k => k.name.includes(`(R-${rUser})`));
                    if(myKeys.length === 0) return bot.sendMessage(chatId, "❌ You have no users.");
                    
                    let allButtons = [];
                    const servers = getServers();
                    myKeys.forEach(k => {
                        let cleanName = k.name.split('|')[0].replace(`(R-${rUser})`, '').trim();
                        const srvIdx = servers.findIndex(s => s.url === k._serverUrl);
                        if (srvIdx !== -1) {
                            allButtons.push([{ text: `👤 ${cleanName} (${k._serverName || 'Srv'})`, callback_data: `rchk_${srvIdx}_${k.id}` }]);
                        }
                    });

                    const chunkSize = 10; 
                    for (let i = 0; i < allButtons.length; i += chunkSize) {
                        const chunk = allButtons.slice(i, i + chunkSize);
                        await bot.sendMessage(chatId, `⚙️ **Select User to Extend (Set ${Math.floor(i / chunkSize) + 1})**`, { 
                            parse_mode: 'Markdown', 
                            reply_markup: { inline_keyboard: chunk } 
                        });
                    }
                } catch(e) { bot.sendMessage(chatId, "⚠️ Server Error"); }
                return;
            }

            if (text === BTN.resell_users) {
                bot.sendMessage(chatId, "🔎 Checking your users...");
                try {
                    const myKeys = await getAllKeysFromAllServers(k => k.name.includes(`(R-${rUser})`));
                    if(myKeys.length === 0) return bot.sendMessage(chatId, "❌ You haven't created any keys yet.");
                    
                    const chunkSize = 10;
                    for (let i = 0; i < myKeys.length; i += chunkSize) {
                        const chunk = myKeys.slice(i, i + chunkSize);
                        let txt = `👥 **User List (Part ${Math.floor(i / chunkSize) + 1})**\n\n`;
                        chunk.forEach(k => {
                            let cleanName = k.name.split('|')[0].replace(`(R-${rUser})`, '').trim();
                            let expireDate = "Unknown";
                            if(k.name.includes('|')) { expireDate = k.name.split('|').pop().trim(); }
                            txt += `👤 ${cleanName} @ ${k._serverName || 'Server'}\n📅 Exp: ${expireDate}\n🔗 ${formatAccessUrl(k.accessUrl, k._serverUrl)}#${encodeURIComponent(cleanName)}\n\n`;
                        });
                        await bot.sendMessage(chatId, txt, { disable_web_page_preview: true });
                    }
                } catch(e) { bot.sendMessage(chatId, "⚠️ Error fetching users."); }
                return;
            }
            return;
        }

        if (text === BTN.reseller) {
            userStates[chatId] = { status: 'RESELLER_LOGIN_USER' };
            return bot.sendMessage(chatId, "🔐 **Reseller Login**\n\nPlease enter your **Username**:", { parse_mode: 'Markdown', reply_markup: { remove_keyboard: true } });
        }

        if (text === BTN.trial) {
            if (!TRIAL_ENABLED) return bot.sendMessage(chatId, "⚠️ Free Trial is currently disabled.");
            if (claimedUsers.includes(chatId)) return bot.sendMessage(chatId, "⚠️ You have already claimed a trial key.");
            bot.sendMessage(chatId, "🖥️ **Select Server for Trial:**", {
                parse_mode: 'Markdown',
                reply_markup: { inline_keyboard: getServerKeyboard('trial_srv') }
            });
            return;
        }

        if (text === BTN.buy) {
            if(!config.plans || config.plans.length === 0) return bot.sendMessage(chatId, "❌ No plans available.");
            const keyboard = config.plans.map((p, i) => [{ text: `${p.days} Days - ${p.gb}GB - ${p.price}Ks`, callback_data: `buy_${i}` }]); 
            bot.sendMessage(chatId, "📅 **Choose Plan:**", { parse_mode: 'Markdown', reply_markup: { inline_keyboard: keyboard } });
            return;
        }

        if (text === BTN.mykey) {
            const userFullName = `${msg.from.first_name}`.trim(); 
            bot.sendMessage(chatId, "🔎 Searching all servers..."); 
            try { 
                const result = await findKeyInAllServers(userFullName, true);
                if (!result) return bot.sendMessage(chatId, "❌ **Key Not Found!**"); 
                const { key, serverUrl, serverName } = result;
                let cleanName = key.name.split('|')[0].trim();
                let finalUrl = formatAccessUrl(key.accessUrl, serverUrl);
                finalUrl += `#${encodeURIComponent(cleanName)}`;
                bot.sendMessage(chatId, `🔑 <b>My Key (${serverName}):</b>\n<code>${finalUrl}</code>`, { parse_mode: 'HTML' }); 
            } catch (e) { bot.sendMessage(chatId, "⚠️ Server Error"); }
            return;
        }

        // --- INFO BUTTON (WITH OFFSET LOGIC) ---
        if (text === BTN.info) {
            const userFullName = `${msg.from.first_name}`.trim(); 
            bot.sendMessage(chatId, "🔎 Checking Status..."); 
            try { 
                const result = await findKeyInAllServers(userFullName, true);
                if (!result) return bot.sendMessage(chatId, "❌ **Account Not Found**"); 
                const { key, metrics, serverName } = result;
                const rawUsage = metrics.bytesTransferredByUserId[key.id] || 0; 
                const rawLimit = key.dataLimit ? key.dataLimit.bytes : 0; 
                
                // *** DISPLAY LOGIC: (Raw - Offset) ***
                const { displayUsed, displayLimit } = getDisplayData(key.id, rawUsage, rawLimit);
                const remaining = displayLimit > 0 ? displayLimit - displayUsed : 0; 
                
                let cleanName = key.name; 
                let expireDate = "Unknown"; 
                if (key.name.includes('|')) { const parts = key.name.split('|'); cleanName = parts[0].trim(); expireDate = parts[parts.length-1].trim(); } 
                
                let statusIcon = "🟢"; let statusText = "Active"; 
                if (rawLimit === 0 || cleanName.startsWith("🔴")) { statusIcon = "🔴"; statusText = "Blocked/Switch OFF"; } 
                else if (isExpired(expireDate)) { statusIcon = "🔴"; statusText = "Expired"; }
                else if (displayLimit > 0 && remaining <= 0) { statusIcon = "🔴"; statusText = "Data Depleted"; }
                
                let percent = displayLimit > 0 ? Math.min((displayUsed / displayLimit) * 100, 100) : 0; 
                const barLength = 10; const fill = Math.round((percent / 100) * barLength); 
                const bar = "█".repeat(fill) + "░".repeat(barLength - fill); 
                
                const msgTxt = `👤 **Name:** ${sanitizeText(cleanName)}\n🖥️ **Server:** ${serverName}\n📡 **Status:** ${statusIcon} ${statusText}\n⏳ **Day:** ${getDaysRemaining(expireDate)}\n⬇️ **Used:** ${formatBytes(displayUsed)}\n🎁 **Free:** ${formatBytes(remaining > 0 ? remaining : 0)}\n📅 **Exp:** ${expireDate}\n\n[${bar}] ${percent.toFixed(1)}%`; 
                bot.sendMessage(chatId, msgTxt, { parse_mode: 'Markdown' }); 
            } catch (e) { bot.sendMessage(chatId, "⚠️ Server Error"); }
            return;
        }

        if (text === BTN.support) {
            const adminUsers = config.admin_username ? config.admin_username.split(',') : []; 
            const keyboard = []; 
            adminUsers.forEach(u => { let cleanUser = u.trim().replace('@', ''); if (cleanUser) keyboard.push([{ text: `💬 Chat with ${cleanUser}`, url: `https://t.me/${cleanUser}` }]); }); 
            if (keyboard.length > 0) bot.sendMessage(chatId, "🆘 **Select an Admin:**", { parse_mode: 'Markdown', reply_markup: { inline_keyboard: keyboard } }); 
            else bot.sendMessage(chatId, "⚠️ Contact not configured.");
            return;
        }

        // --- ADMIN PANEL ---
        if (text === "👮‍♂️ Admin Panel" && isAdmin(chatId)) {
            const servers = getServers();
            
            let keyboard = [
                [{ text: "📢 Broadcast Message", callback_data: "admin_broadcast" }], 
                [{ text: "📊 DATABASE (Total Stats)", callback_data: "admin_db" }],
                [{ text: "📂 ALL SERVERS (Show Keys)", callback_data: "admin_all" }],
                [{ text: "👥 Reseller Users", callback_data: "admin_resellers" }],
                [{ text: "💰 Reseller Topup", callback_data: "admin_topup" }],
                [{ text: "⚙️ System Backup & Restore", callback_data: "admin_backup_menu" }] // *** BACKUP MENU BUTTON ***
            ];
            
            servers.forEach((s, idx) => {
                let sName = s.name || `Server ${idx + 1}`;
                keyboard.push([{ text: `🖥️ ${sName}`, callback_data: `admin_srv_${idx}` }]);
            });

            bot.sendMessage(chatId, "🎛 **Admin Control Panel**\n\nSelect an option to manage:", { parse_mode: 'Markdown', reply_markup: { inline_keyboard: keyboard } });
            return;
        }
    });

    bot.on('callback_query', async (q) => { 
        const chatId = q.message.chat.id; 
        const data = q.data; 
        const userFullName = `${q.from.first_name}`.trim();
        const adminName = q.from.first_name; 

        if (data.startsWith('trial_srv_')) {
            if (!TRIAL_ENABLED) return bot.sendMessage(chatId, "Trial Disabled.");
            if (claimedUsers.includes(chatId)) return bot.sendMessage(chatId, "Already claimed.");
            
            const serverIndex = parseInt(data.split('_')[2]);
            bot.sendMessage(chatId, "⏳ Creating Test Key...");
            try {
                const expireDate = getMyanmarDate(TRIAL_DAYS);
                const userFullName = `${q.from.first_name}`.trim(); 
                const username = q.from.username ? `#${q.from.username}` : '';
                const name = `TEST_${userFullName.replace(/\|/g, '').trim()} ${username} | ${expireDate}`; 
                const limitBytes = Math.floor(TRIAL_GB * 1024 * 1024 * 1024);
                
                const data = await createKeyOnServer(serverIndex, name, limitBytes);
                
                claimedUsers.push(chatId); fs.writeFileSync(CLAIM_FILE, JSON.stringify(claimedUsers));
                let finalUrl = formatAccessUrl(data.accessUrl, data._serverUrl); finalUrl += `#${encodeURIComponent(name.split('|')[0].trim())}`;
                
                bot.deleteMessage(chatId, q.message.message_id);
                bot.sendMessage(chatId, `🎉 <b>Free Trial Created!</b>\n\n👤 Name: ${userFullName}\n🖥️ Server: ${data._serverName}\n📅 Duration: ${TRIAL_DAYS} Days\n📦 Data: ${TRIAL_GB} GB\n📅 Expire: ${expireDate}\n\n🔗 <b>Key:</b>\n<code>${finalUrl}</code>`, { parse_mode: 'HTML' }); 
            } catch (e) { bot.sendMessage(chatId, "❌ Error creating test key."); }
            return;
        }

        if (data.startsWith('resell_buy_')) {
            const rUser = resellerSessions[chatId];
            if (!rUser) return bot.answerCallbackQuery(q.id, { text: "Session Expired. Login again.", show_alert: true });
            const planIdx = parseInt(data.split('_')[2]);
            const plansToUse = (config.reseller_plans && config.reseller_plans.length > 0) ? config.reseller_plans : config.plans;
            const p = plansToUse[planIdx];
            const reseller = resellers.find(r => r.username === rUser);
            if(parseInt(reseller.balance) < parseInt(p.price)) {
                return bot.answerCallbackQuery(q.id, { text: `⚠️ Insufficient Balance!\nNeed: ${p.price} Ks`, show_alert: true });
            }
            userStates[chatId] = { status: 'RESELLER_SELECT_SERVER', plan: p, reseller: rUser };
            bot.sendMessage(chatId, "🖥️ **Select Server:**", {
                parse_mode: 'Markdown',
                reply_markup: { inline_keyboard: getServerKeyboard('rsrv') }
            });
            return;
        }

        if (data.startsWith('rsrv_')) {
            const rUser = resellerSessions[chatId];
            if (!rUser) return bot.sendMessage(chatId, "❌ Session Expired.");
            
            const serverIndex = parseInt(data.split('_')[1]);
            if (!userStates[chatId] || userStates[chatId].status !== 'RESELLER_SELECT_SERVER') {
                 return bot.sendMessage(chatId, "❌ Flow Error. Please start over.");
            }
            userStates[chatId].serverIndex = serverIndex;
            userStates[chatId].status = 'RESELLER_ENTER_NAME';
            const p = userStates[chatId].plan;
            
            bot.deleteMessage(chatId, q.message.message_id);
            bot.sendMessage(chatId, `👤 **Enter Customer Name:**\n(Plan: ${p.days} Days / ${p.gb} GB)\n(Server Selected)`, { parse_mode: 'Markdown', reply_markup: { force_reply: true } });
            return;
        }

        if (data.startsWith('buy_') && !data.startsWith('buy_srv_')) { 
            const planIdx = parseInt(data.split('_')[1]);
            bot.sendMessage(chatId, "🖥️ **Select Server:**", {
                parse_mode: 'Markdown',
                reply_markup: { inline_keyboard: getServerKeyboard(`buy_srv_${planIdx}`) }
            });
            return;
        } 

        if (data.startsWith('buy_srv_')) {
            const parts = data.split('_');
            const planIdx = parseInt(parts[2]);
            const serverIdx = parseInt(parts[3]);
            const p = config.plans[planIdx];
            const servers = getServers();
            const sName = servers[serverIdx].name || "Server";

            let payTxt = ""; 
            if(config.payments) config.payments.forEach(pay => payTxt += `▪️ ${pay.name}: \`${pay.num}\` (${pay.owner})\n`); 
            
            userStates[chatId] = { 
                status: 'WAITING_SLIP', 
                plan: p, 
                name: userFullName, 
                type: 'NEW', 
                username: q.from.username,
                targetServerIndex: serverIdx,
                targetServerName: sName
            }; 
            
            bot.deleteMessage(chatId, q.message.message_id);
            bot.sendMessage(chatId, `✅ **Plan:** ${p.days} Days (${p.gb}GB)\n🖥️ **Server:** ${sName}\n💰 **Price:** ${p.price} Ks\n\n💸 **Payments:**\n${payTxt}\n⚠️ ငွေလွှဲပြီးပါက ပြေစာ (Screenshot) ပို့ပေးပါ။`, {parse_mode: 'Markdown'}); 
            return;
        }

        // --- ADMIN CALLBACKS ---
        if (isAdmin(chatId)) {
            // *** NEW: BACKUP & RESTORE CALLS ***
            if (data === 'admin_backup_menu') {
                const bkMenu = [
                    [{ text: "📤 Export Backup File", callback_data: "admin_backup_export" }],
                    [{ text: "📥 Import Restore File", callback_data: "admin_backup_import" }]
                ];
                bot.sendMessage(chatId, "⚙️ **System Backup & Restore Control**\n\nဒီနေရာမှာ Server Configs, Bot Settings, Resellers, Shop Plans နဲ့ User Databases တွေကို Backup/Restore လုပ်နိုင်ပါတယ်။", {
                    parse_mode: 'Markdown',
                    reply_markup: { inline_keyboard: bkMenu }
                });
                return;
            }

            if (data === 'admin_backup_export') {
                bot.answerCallbackQuery(q.id, { text: "Generating Backup..." });
                try {
                    const backupData = {
                        config: fs.existsSync(CONFIG_FILE) ? JSON.parse(fs.readFileSync(CONFIG_FILE)) : {},
                        resellers: fs.existsSync(RESELLER_FILE) ? JSON.parse(fs.readFileSync(RESELLER_FILE)) : [],
                        claimed_users: fs.existsSync(CLAIM_FILE) ? JSON.parse(fs.readFileSync(CLAIM_FILE)) : [],
                        blocked_registry: fs.existsSync(BLOCKED_FILE) ? JSON.parse(fs.readFileSync(BLOCKED_FILE)) : {},
                        all_users: fs.existsSync(ALL_USERS_FILE) ? JSON.parse(fs.readFileSync(ALL_USERS_FILE)) : [],
                        usage_offsets: fs.existsSync(OFFSET_FILE) ? JSON.parse(fs.readFileSync(OFFSET_FILE)) : {}
                    };
                    const backupFilename = `VPN_Backup_${moment().tz("Asia/Yangon").format('YYYYMMDD_HHmmss')}.json`;
                    fs.writeFileSync(backupFilename, JSON.stringify(backupData, null, 4));
                    
                    await bot.sendDocument(chatId, backupFilename, { caption: "✅ **VPN Shop System Backup Complete!**\n⚠️ ဒီဖိုင်ကို လုံခြုံစွာသိမ်းဆည်းပါ။ ပြန်ပြီး Restore လုပ်လိုပါက ဤဖိုင်ကို သုံးနိုင်ပါသည်။" }, {contentType: 'application/json'});
                    fs.unlinkSync(backupFilename); // Clean local file after send
                } catch (e) {
                    bot.sendMessage(chatId, `❌ Backup ထုတ်ယူရာတွင် အမှားအယွင်းရှိခဲ့သည်- ${e.message}`);
                }
                return;
            }

            if (data === 'admin_backup_import') {
                userStates[chatId] = { status: 'WAITING_BACKUP_FILE' };
                bot.sendMessage(chatId, "📥 **Backup File (.json) ကို ပို့ပေးပါ။**\n\n⚠️ သတိပြုရန်- ဖိုင်ဆောက်တည်ပုံ မှန်ကန်သော Backup ဖိုင်ကိုသာ လက်ခံမည်ဖြစ်ပြီး လက်ရှိ Settings အားလုံးကို အစားထိုးသွားမည်ဖြစ်သည်။ ဖျက်လိုပါက /start နှိပ်ပါ။", { parse_mode: 'Markdown' });
                return;
            }

            if (data === 'admin_broadcast') {
                userStates[chatId] = { status: 'ADMIN_BROADCAST_MSG' };
                bot.sendMessage(chatId, `📢 **Broadcast Message**\n\nTotal Users: ${allUsers.length}\n\nPlease enter the message you want to send to ALL users:`, { parse_mode: 'Markdown', reply_markup: { force_reply: true } });
                return;
            }

            if (data === 'admin_topup') {
                 if (!resellers || resellers.length === 0) return bot.sendMessage(chatId, "❌ No resellers found.");
                 let keyboard = [];
                 resellers.forEach(r => {
                    keyboard.push([{ text: `💰 ${r.username} (Bal: ${r.balance})`, callback_data: `rtop_${r.username}` }]);
                 });
                 bot.sendMessage(chatId, "💰 **Select Reseller to Topup:**", { parse_mode: 'Markdown', reply_markup: { inline_keyboard: keyboard } });
                 return;
            }

            if (data.startsWith('rtop_')) {
                const targetReseller = data.split('_')[1];
                userStates[chatId] = { status: 'ADMIN_TOPUP_AMOUNT', targetReseller: targetReseller };
                bot.sendMessage(chatId, `💰 **Enter Topup Amount for ${targetReseller}:**\n(Enter negative amount to deduct, e.g., -1000)`, { parse_mode: 'Markdown', reply_markup: { force_reply: true } });
                return;
            }

            if (data === 'admin_resellers') {
                if (!resellers || resellers.length === 0) return bot.sendMessage(chatId, "❌ No resellers registered.");
                let keyboard = [];
                resellers.forEach(r => {
                    keyboard.push([{ text: `👤 ${r.username} (${r.balance} Ks)`, callback_data: `admin_rlist_${r.username}` }]);
                });
                bot.sendMessage(chatId, "👥 **Select a Reseller:**", { parse_mode: 'Markdown', reply_markup: { inline_keyboard: keyboard } });
                return;
            }

            // --- ADMIN RESELLER LIST (PAGINATED 10/msg) ---
            if (data.startsWith('admin_rlist_')) {
                const targetReseller = data.split('_')[2];
                bot.sendMessage(chatId, `🔎 Finding users for **${targetReseller}**...`, { parse_mode: 'Markdown' });
                try {
                    const keys = await getAllKeysFromAllServers(k => k.name.includes(`(R-${targetReseller})`));
                    keys.sort((a,b) => parseInt(a.id) - parseInt(b.id)); 
                    if (keys.length === 0) return bot.sendMessage(chatId, "❌ No users found for this reseller.");

                    const chunkSize = 10;
                    const servers = getServers();
                    for (let i = 0; i < keys.length; i += chunkSize) {
                        const chunk = keys.slice(i, i + chunkSize);
                        let txt = `👤 **${targetReseller}'s Users (Part ${Math.floor(i / chunkSize) + 1})**\n\n`;
                        let kb = [];
                        chunk.forEach(k => {
                            let name = k.name || "No Name";
                            let sName = k._serverName || "Srv";
                            txt += `🆔 ${k.id} (${sName}) : ${sanitizeText(name)}\n`;
                            let btnName = `[${sName}] ${name}`;
                            if(btnName.length > 25) btnName = btnName.substring(0,25)+"..";
                            const srvIdx = servers.findIndex(s => s.url === k._serverUrl);
                            if(srvIdx !== -1) { kb.push([{ text: btnName, callback_data: `chk_${srvIdx}_${k.id}` }]); }
                        });
                        await bot.sendMessage(chatId, txt, { parse_mode: 'Markdown', reply_markup: { inline_keyboard: kb } });
                    }
                } catch(e) { bot.sendMessage(chatId, "Error fetching reseller keys."); }
                return;
            }

            if (data === 'admin_db') {
                bot.answerCallbackQuery(q.id, { text: "Calculating Stats..." });
                const servers = getServers();
                let totalKeys = 0;
                let totalBytes = 0;
                try {
                    const promises = servers.map(async (srv) => {
                        try {
                            const [kRes, mRes] = await Promise.all([
                                axiosClient.get(`${srv.url}/access-keys`),
                                axiosClient.get(`${srv.url}/metrics/transfer`)
                            ]);
                            return { keys: kRes.data.accessKeys.length, metrics: mRes.data.bytesTransferredByUserId };
                        } catch(e) { return { keys: 0, metrics: {} }; }
                    });
                    const results = await Promise.all(promises);
                    results.forEach(res => {
                        totalKeys += res.keys;
                        Object.values(res.metrics).forEach(bytes => totalBytes += bytes);
                    });
                    bot.sendMessage(chatId, `📊 **DATABASE STATISTICS**\n\n💾 **Total Servers:** ${servers.length}\n🔑 **Total Keys:** ${totalKeys}\n📡 **Total Traffic:** ${formatBytes(totalBytes)}\n👥 **Total Bot Users:** ${allUsers.length}`, { parse_mode: 'Markdown' });
                } catch(e) { bot.sendMessage(chatId, "❌ Error fetching stats."); }
                return;
            }

            // --- ADMIN ALL SERVERS (PAGINATED 10/msg) ---
            if (data === 'admin_all') {
                bot.sendMessage(chatId, "⌛ Loading ALL Users..."); 
                try { 
                    const keys = await getAllKeysFromAllServers();
                    keys.sort((a,b) => parseInt(a.id) - parseInt(b.id)); 
                    const chunkSize = 10;
                    const servers = getServers();
                    for (let i = 0; i < keys.length; i += chunkSize) {
                        const chunk = keys.slice(i, i + chunkSize);
                        let txt = `👥 **ALL USERS (Part ${Math.floor(i / chunkSize) + 1})**\n\n`; 
                        let kb = []; 
                        chunk.forEach(k => { 
                            let name = k.name || "No Name"; 
                            txt += `🆔 ${k.id} : ${sanitizeText(name)}\n`; 
                            let btnName = `[${k._serverName}] ${name}`; 
                            if(btnName.length > 25) btnName = btnName.substring(0,25)+".."; 
                            const srvIdx = servers.findIndex(s => s.url === k._serverUrl);
                            if(srvIdx !== -1) { kb.push([{ text: btnName, callback_data: `chk_${srvIdx}_${k.id}` }]); }
                        }); 
                        await bot.sendMessage(chatId, txt, { parse_mode: 'Markdown', reply_markup: { inline_keyboard: kb } }); 
                    }
                } catch(e) { bot.sendMessage(chatId, "Error fetching list"); }
                return;
            }

            // --- ADMIN SPECIFIC SERVER (PAGINATED 10/msg) ---
            if (data.startsWith('admin_srv_')) {
                const srvIdx = parseInt(data.split('_')[2]);
                const servers = getServers();
                const targetSrv = servers[srvIdx];
                if (!targetSrv) return bot.sendMessage(chatId, "Server not found.");
                bot.sendMessage(chatId, `⌛ Loading users from **${targetSrv.name || 'Server'}**...`, { parse_mode: 'Markdown' });
                try {
                    const keys = await getKeysFromSpecificServer(srvIdx);
                    keys.sort((a,b) => parseInt(a.id) - parseInt(b.id));
                    const chunkSize = 10;
                    for (let i = 0; i < keys.length; i += chunkSize) {
                        const chunk = keys.slice(i, i + chunkSize);
                        let txt = `🖥️ **${targetSrv.name} (Part ${Math.floor(i / chunkSize) + 1})**\n\n`;
                        let kb = [];
                        chunk.forEach(k => {
                            let name = k.name || "No Name"; 
                            txt += `🆔 ${k.id} : ${sanitizeText(name)}\n`; 
                            let btnName = `[${k.id}] ${name}`; 
                            if(btnName.length > 20) btnName = btnName.substring(0,20)+".."; 
                            kb.push([{ text: btnName, callback_data: `chk_${srvIdx}_${k.id}` }]); 
                        }); 
                        await bot.sendMessage(chatId, txt, { parse_mode: 'Markdown', reply_markup: { inline_keyboard: kb } });
                    }
                } catch(e) { bot.sendMessage(chatId, "Error fetching keys from server."); }
                return;
            }

             if (data.startsWith('chk_')) { 
                const parts = data.split('_');
                let serverIndex = -1;
                let kid = parts[1];

                if (parts.length === 3) {
                    serverIndex = parseInt(parts[1]);
                    kid = parts[2];
                }

                try { 
                    let result = null;
                    if (serverIndex !== -1) {
                        const servers = getServers();
                        if (servers[serverIndex]) {
                            const srv = servers[serverIndex];
                            try {
                                const [kRes, mRes] = await Promise.all([
                                    axiosClient.get(`${srv.url}/access-keys`),
                                    axiosClient.get(`${srv.url}/metrics/transfer`)
                                ]);
                                const key = kRes.data.accessKeys.find(k => String(k.id) === String(kid));
                                if (key) {
                                    result = { key, metrics: mRes.data, serverUrl: srv.url, serverName: srv.name };
                                }
                            } catch (e) { console.log("Specific server fetch error"); }
                        }
                    } else {
                         result = await findKeyInAllServers(kid);
                    }

                    if(!result) return bot.sendMessage(chatId, "Key not found or Server Error"); 
                    
                    const { key, metrics, serverName } = result;
                    const rawUsage = metrics.bytesTransferredByUserId[key.id] || 0; 
                    const rawLimit = key.dataLimit ? key.dataLimit.bytes : 0; 
                    
                    // *** DISPLAY LOGIC (OFFSET) ***
                    const { displayUsed, displayLimit } = getDisplayData(key.id, rawUsage, rawLimit);
                    const remaining = displayLimit > 0 ? displayLimit - displayUsed : 0;

                    let cleanName = key.name; let expireDate = "N/A"; 
                    if (key.name.includes('|')) { const parts = key.name.split('|'); cleanName = parts[0].trim(); expireDate = parts[parts.length-1].trim(); } 
                    
                    let statusIcon = "🟢"; let statusText = "Active"; 
                    if (rawLimit === 0 || cleanName.startsWith("🔴")) { 
                        statusIcon = "🔴"; statusText = "Blocked/OFF"; 
                    } 
                    else if (isExpired(expireDate)) { statusIcon = "🔴"; statusText = "Expired"; } 
                    
                    let percent = displayLimit > 0 ? Math.min((displayUsed / displayLimit) * 100, 100) : 0; const barLength = 10; const fill = Math.round((percent / 100) * barLength); const bar = "░".repeat(barLength).split('').map((c, i) => i < fill ? "█" : c).join(''); 
                    const msg = `👮 User Management\n---------------------\n👤 Name: ${cleanName}\n🖥️ Server: ${serverName}\n📡 Status: ${statusIcon} ${statusText}\n⏳ Remaining: ${getDaysRemaining(expireDate)}\n⬇️ Used: ${formatBytes(displayUsed)}\n🎁 Free: ${displayLimit ? formatBytes(remaining) : 'Unl'}\n📅 Expire: ${expireDate}\n\n${bar} ${percent.toFixed(1)}%`; 
                    bot.sendMessage(chatId, msg, { reply_markup: { inline_keyboard: [[{ text: "⏳ RENEW / EXTEND", callback_data: `adm_ext_${key.id}` }], [{ text: "🗑️ DELETE", callback_data: `del_${key.id}` }]] } }); 
                } catch(e) {} 
            } 

            if (data.startsWith('adm_ext_')) {
                const kid = data.split('_')[2];
                if (!config.plans || config.plans.length === 0) return bot.sendMessage(chatId, "❌ No public plans configured.");
                const keyboard = config.plans.map((p, i) => [{ text: `+${p.days} Days (${p.gb}GB)`, callback_data: `adm_renew_${kid}_${i}` }]);
                bot.sendMessage(chatId, "👮‍♂️ **Admin Renew: Select Plan**", { parse_mode: 'Markdown', reply_markup: { inline_keyboard: keyboard } });
            }
            if (data.startsWith('adm_renew_')) {
                const parts = data.split('_'); const keyId = parts[2]; const planIdx = parseInt(parts[3]); const p = config.plans[planIdx];
                try {
                    const result = await findKeyInAllServers(keyId);
                    if(!result) return bot.sendMessage(chatId, "Key not found");
                    const { key, serverUrl, metrics } = result;

                    // *** RESET & TOP UP LOGIC ***
                    const currentRaw = metrics.bytesTransferredByUserId[keyId] || 0;
                    
                    // 1. *** FORCE SYNC: SAVE OFFSET TO FILE ***
                    usageOffsets[keyId] = currentRaw;
                    saveOffsets(); 

                    // 2. SET NEW LIMIT (Raw Usage + New Plan Amount)
                    const planBytes = Math.floor(p.gb * 1024 * 1024 * 1024);
                    const finalLimitBytes = currentRaw + planBytes;

                    // 3. RESET DATE
                    let newDate = getMyanmarDate(p.days);

                    let cleanName = key.name.split('|')[0].trim();
                    cleanName = cleanName.replace(/^🔴\s*\[BLOCKED\]\s*/, '').replace(/^🔴\s*/, '');
                    
                    await axiosClient.put(`${serverUrl}/access-keys/${keyId}/name`, { name: `${cleanName} | ${newDate}` });
                    await axiosClient.put(`${serverUrl}/access-keys/${keyId}/data-limit`, { limit: { bytes: finalLimitBytes } });
                    
                    bot.deleteMessage(chatId, q.message.message_id);
                    bot.sendMessage(chatId, `✅ **Admin Renew Success!**\n\n👤 User: ${cleanName}\n📅 New Expire: ${newDate}\n📦 Data: ${p.gb} GB (Reset & TopUp)`, { parse_mode: 'Markdown' });
                } catch(e) { bot.sendMessage(chatId, "❌ Error extending key."); }
            }
            if (data.startsWith('del_')) { 
                try {
                    const result = await findKeyInAllServers(data.split('_')[1]);
                    if(result) {
                        await axiosClient.delete(`${result.serverUrl}/access-keys/${result.key.id}`); 
                        bot.sendMessage(chatId, "✅ User Deleted."); 
                        bot.deleteMessage(chatId, q.message.message_id); 
                    } else { bot.sendMessage(chatId, "Key not found"); }
                } catch(e){}
            } 
            if (data.startsWith('approve_')) { 
                const buyerId = data.split('_')[1]; 
                if (!userStates[buyerId]) return bot.answerCallbackQuery(q.id, { text: "⚠️ Processed!", show_alert: true });
                const { plan, name, username, targetServerIndex } = userStates[buyerId]; 
                bot.editMessageCaption(`✅ Approved by ${adminName}`, { chat_id: chatId, message_id: q.message.message_id }); 
                ADMIN_IDS.forEach(aid => { if (String(aid) !== String(chatId)) bot.sendMessage(aid, `🔔 **ORDER APPROVED**\n\n👤 Customer: ${name}\n📦 Plan: ${plan.days}D / ${plan.gb}GB\n👮‍♂️ Action: **${adminName}**`, { parse_mode: 'Markdown' }); });
                try { 
                    const expireDate = getMyanmarDate(plan.days); 
                    const limit = plan.gb * 1024 * 1024 * 1024; 
                    let finalName = `${name.replace(/\|/g,'').trim()} #${username || ''} | ${expireDate}`; 
                    
                    const data = await createKeyOnServer(targetServerIndex, finalName, limit);
                    
                    let finalUrl = formatAccessUrl(data.accessUrl, data._serverUrl); finalUrl += `#${encodeURIComponent(finalName.split('|')[0].trim())}`;
                    bot.sendMessage(buyerId, `🎉 <b>Purchase Success!</b>\n\n👤 Name: ${name}\n🖥️ Server: ${data._serverName}\n📅 Expire: ${expireDate}\n\n🔗 <b>Key:</b>\n<code>${finalUrl}</code>`, { parse_mode: 'HTML' }); 
                    delete userStates[buyerId]; 
                } catch(e) { bot.sendMessage(ADMIN_IDS[0], "❌ Error creating key on selected server."); } 
            } 
            if (data.startsWith('reject_')) { 
                const buyerId = data.split('_')[1]; 
                if (!userStates[buyerId]) return bot.answerCallbackQuery(q.id, { text: "⚠️ Processed!", show_alert: true });
                const { name, plan } = userStates[buyerId];
                bot.sendMessage(buyerId, "❌ Your order was rejected."); 
                bot.editMessageCaption(`❌ Rejected by ${adminName}`, { chat_id: chatId, message_id: q.message.message_id }); 
                ADMIN_IDS.forEach(aid => { if (String(aid) !== String(chatId)) bot.sendMessage(aid, `🚫 **ORDER REJECTED**\n\n👤 Customer: ${name}\n📦 Plan: ${plan.days} Days\n👮‍♂️ Action: **${adminName}**`, { parse_mode: 'Markdown' }); });
                delete userStates[buyerId];
            } 
        } 

        // --- RESELLER ACTIONS ---
        if (data.startsWith('rchk_')) {
            const rUser = resellerSessions[chatId];
            if (!rUser) return bot.answerCallbackQuery(q.id, { text: "Session Expired.", show_alert: true });
            const parts = data.split('_');
            const srvIdx = parseInt(parts[1]);
            const keyId = parts[2];
            const servers = getServers();
            const targetServer = servers[srvIdx];
            if (!targetServer) return bot.sendMessage(chatId, "⚠️ Server Error.");
            try { 
                const [kRes, mRes] = await Promise.all([
                    axiosClient.get(`${targetServer.url}/access-keys`),
                    axiosClient.get(`${targetServer.url}/metrics/transfer`)
                ]);
                const key = kRes.data.accessKeys.find(k => String(k.id) === String(keyId));
                if(!key) return bot.sendMessage(chatId, "⚠️ Key not found.");
                if(!key.name.includes(`(R-${rUser})`)) return bot.sendMessage(chatId, "⚠️ Access Denied. Not your user.");
                const rawUsage = mRes.data.bytesTransferredByUserId[key.id] || 0; 
                const rawLimit = key.dataLimit ? key.dataLimit.bytes : 0; 
                
                // *** DISPLAY LOGIC (OFFSET) ***
                const { displayUsed, displayLimit } = getDisplayData(key.id, rawUsage, rawLimit);
                const remaining = displayLimit > 0 ? displayLimit - displayUsed : 0;

                let cleanName = key.name; let expireDate = "N/A"; 
                if (key.name.includes('|')) { 
                    const nParts = key.name.split('|'); 
                    cleanName = nParts[0].replace(`(R-${rUser})`,'').trim(); 
                    expireDate = nParts[nParts.length-1].trim(); 
                } 
                let statusIcon = "🟢"; let statusText = "Active"; 
                if (rawLimit === 0 || cleanName.startsWith("🔴")) { statusIcon = "🔴"; statusText = "Blocked/OFF"; } 
                else if (isExpired(expireDate)) { statusIcon = "🔴"; statusText = "Expired"; } 
                let percent = displayLimit > 0 ? Math.min((displayUsed / displayLimit) * 100, 100) : 0; 
                const barLength = 10; const fill = Math.round((percent / 100) * barLength); 
                const bar = "█".repeat(fill) + "░".repeat(barLength - fill); 
                const msg = `⚙️ **User Management System**\n--------------------------------\n👤 **Name:** ${cleanName}\n🖥️ **Server:** ${targetServer.name}\n📡 **Status:** ${statusIcon} ${statusText}\n⏳ **Remaining:** ${getDaysRemaining(expireDate)}\n⬇️ **Used:** ${formatBytes(displayUsed)}\n🎁 **Limit:** ${displayLimit ? formatBytes(displayLimit) : 'Unlimited'}\n📅 **Expire:** ${expireDate}\n\n[${bar}] ${percent.toFixed(1)}%`;
                bot.sendMessage(chatId, msg, { parse_mode: 'Markdown', reply_markup: { inline_keyboard: [
                    [{ text: "⏳ Extend / Renew", callback_data: `rext_${srvIdx}_${key.id}` }], 
                    [{ text: "🗑️ Delete User", callback_data: `rdel_${srvIdx}_${key.id}` }]
                ] } }); 
            } catch(e) { bot.sendMessage(chatId, "Error fetching details"); }
        }

        if (data.startsWith('rdel_')) {
            const rUser = resellerSessions[chatId];
            if (!rUser) return bot.answerCallbackQuery(q.id, { text: "Session Expired.", show_alert: true });
            const parts = data.split('_');
            const srvIdx = parseInt(parts[1]);
            const keyId = parts[2];
            const servers = getServers();
            const targetServer = servers[srvIdx];
            try {
                const kRes = await axiosClient.get(`${targetServer.url}/access-keys`);
                const key = kRes.data.accessKeys.find(k => String(k.id) === String(keyId));
                if (key && key.name.includes(`(R-${rUser})`)) {
                     await axiosClient.delete(`${targetServer.url}/access-keys/${keyId}`); 
                     bot.deleteMessage(chatId, q.message.message_id); 
                     bot.sendMessage(chatId, "✅ User Deleted."); 
                } else {
                     bot.sendMessage(chatId, "❌ Delete Failed: Key not found or Access Denied.");
                }
            } catch(e) { bot.sendMessage(chatId, "Delete Failed."); }
        }

        if (data.startsWith('rext_')) {
            const rUser = resellerSessions[chatId];
            if (!rUser) return bot.answerCallbackQuery(q.id, { text: "Session Expired.", show_alert: true });
            const parts = data.split('_');
            const srvIdx = parts[1]; 
            const keyId = parts[2];
            const plansToUse = (config.reseller_plans && config.reseller_plans.length > 0) ? config.reseller_plans : config.plans;
            const keyboard = plansToUse.map((p, i) => [{ text: `+${p.days} Days (${p.gb}GB) - ${p.price}Ks`, callback_data: `rxp_${srvIdx}_${keyId}_${i}` }]);
            bot.sendMessage(chatId, "📅 **Choose Extension Plan:**", { parse_mode: 'Markdown', reply_markup: { inline_keyboard: keyboard } });
        }

        if (data.startsWith('rxp_')) {
            const rUser = resellerSessions[chatId];
            if (!rUser) return bot.answerCallbackQuery(q.id, { text: "Session Expired.", show_alert: true });
            const parts = data.split('_'); 
            const srvIdx = parseInt(parts[1]);
            const keyId = parts[2]; 
            const planIdx = parseInt(parts[3]);
            const servers = getServers();
            const targetServer = servers[srvIdx];
            const plansToUse = (config.reseller_plans && config.reseller_plans.length > 0) ? config.reseller_plans : config.plans;
            const p = plansToUse[planIdx];
            const resellerIdx = resellers.findIndex(r => r.username === rUser);
            if(resellers[resellerIdx].balance < parseInt(p.price)) return bot.answerCallbackQuery(q.id, { text: "⚠️ Insufficient Balance!", show_alert: true });
            try {
                const [kRes, mRes] = await Promise.all([
                    axiosClient.get(`${targetServer.url}/access-keys`),
                    axiosClient.get(`${targetServer.url}/metrics/transfer`)
                ]);
                const key = kRes.data.accessKeys.find(k => String(k.id) === String(keyId));
                if(!key) return bot.sendMessage(chatId, "Key not found");

                // *** RESET & TOP UP LOGIC FOR RESELLER ***
                const currentRaw = mRes.data.bytesTransferredByUserId[keyId] || 0;
                
                // 1. *** FORCE SYNC: SAVE OFFSET TO FILE ***
                usageOffsets[keyId] = currentRaw;
                saveOffsets();

                // 2. SET NEW LIMIT
                const planBytes = Math.floor(p.gb * 1024 * 1024 * 1024);
                const finalLimitBytes = currentRaw + planBytes;

                // 3. RESET DATE
                let newDate = getMyanmarDate(p.days);

                resellers[resellerIdx].balance -= parseInt(p.price);
                fs.writeFileSync(RESELLER_FILE, JSON.stringify(resellers, null, 4));

                let cleanName = key.name.split('|')[0].trim();
                cleanName = cleanName.replace(/^🔴\s*\[BLOCKED\]\s*/, '').replace(/^🔴\s*/, '');
                
                await axiosClient.put(`${targetServer.url}/access-keys/${keyId}/name`, { name: `${cleanName} | ${newDate}` });
                await axiosClient.put(`${targetServer.url}/access-keys/${keyId}/data-limit`, { limit: { bytes: finalLimitBytes } });
                
                bot.deleteMessage(chatId, q.message.message_id);
                bot.sendMessage(chatId, `✅ **Extension Successful!**\n\n👤 User: ${cleanName}\n📅 New Expire: ${newDate}\n📦 Data: ${p.gb} GB (Reset & TopUp)`, { parse_mode: 'Markdown' });
            } catch(e) { bot.sendMessage(chatId, "❌ Error extending key."); }
        }
    });

    bot.on('photo', (msg) => { 
        const chatId = msg.chat.id; 
        if (userStates[chatId] && userStates[chatId].status === 'WAITING_SLIP') { 
            const { plan, name, type, targetServerName } = userStates[chatId]; 
            bot.sendMessage(chatId, "📩 Slip Received. Please wait."); 
            ADMIN_IDS.forEach(adminId => { 
                bot.sendPhoto(adminId, msg.photo[msg.photo.length - 1].file_id, { 
                    caption: `💰 Order: ${name}\n📦 ${plan.days}D / ${plan.gb}GB\n🖥️ Server: ${targetServerName}\nType: ${type}`, 
                    reply_markup: { inline_keyboard: [[{ text: "✅ Approve", callback_data: `approve_${chatId}` }, { text: "❌ Reject", callback_data: `reject_${chatId}` }]] } 
                }).catch(e => {}); 
            }); 
        } 
    });

    // *** NEW: RECEIVE BACKUP JSON FILE & RESTORE LOGIC ***
    bot.on('document', async (msg) => {
        const chatId = msg.chat.id;
        if (isAdmin(chatId) && userStates[chatId] && userStates[chatId].status === 'WAITING_BACKUP_FILE') {
            if (!msg.document.file_name.endsWith('.json')) {
                return bot.sendMessage(chatId, "❌ မှားယွင်းနေပါသည်။ .json format Backup file ကိုသာ ပို့ပေးပါ။");
            }
            bot.sendMessage(chatId, "⏳ ဖိုင်ကို စစ်ဆေးပြီး Restore လုပ်နေပါသည်...");
            try {
                const fileUrl = await bot.getFileLink(msg.document.file_id);
                const response = await axios.get(fileUrl);
                const data = response.data;

                // Structure check to make sure it's a valid backup
                if (data && data.config && data.resellers && data.usage_offsets) {
                    
                    // Overwrite files safely
                    if (data.config) fs.writeFileSync(CONFIG_FILE, JSON.stringify(data.config, null, 4));
                    if (data.resellers) fs.writeFileSync(RESELLER_FILE, JSON.stringify(data.resellers, null, 4));
                    if (data.claimed_users) fs.writeFileSync(CLAIM_FILE, JSON.stringify(data.claimed_users, null, 4));
                    if (data.blocked_registry) fs.writeFileSync(BLOCKED_FILE, JSON.stringify(data.blocked_registry, null, 4));
                    if (data.all_users) fs.writeFileSync(ALL_USERS_FILE, JSON.stringify(data.all_users, null, 4));
                    if (data.usage_offsets) fs.writeFileSync(OFFSET_FILE, JSON.stringify(data.usage_offsets, null, 4));

                    bot.sendMessage(chatId, "✅ **SYSTEM RESTORE SUCCESSFUL!**\n\nSettings, Resellers, Plans နဲ့ ဇယားများအားလုံးကို အောင်မြင်စွာ ပြန်သွင်းပြီးပါပြီ။ Bot ကို Restart လုပ်နေပါသည်။", {
                        reply_markup: { keyboard: getMainMenu(chatId), resize_keyboard: true }
                    });
                    delete userStates[chatId];
                    
                    // Hot Reload and Apply Config
                    setTimeout(() => { loadConfig(); startBot(); }, 1500);
                } else {
                    bot.sendMessage(chatId, "❌ ဖိုင်တည်ဆောက်ပုံ ပျက်စီးနေပါသည်။ စနစ်တကျ ထုတ်ယူထားသော Backup ဖိုင် မဟုတ်ပါ။");
                }
            } catch (e) {
                bot.sendMessage(chatId, `❌ Restore လုပ်ရာတွင် အမှားအယွင်းရှိသည်- ${e.message}`);
            }
        }
    });

    async function runGuardian() { 
        if (isGuardianRunning) return;
        isGuardianRunning = true;

        try { 
            const keys = await getAllKeysFromAllServers();
            const now = Date.now(); 
            const today = moment().tz("Asia/Yangon").startOf('day');

            for (const key of keys) { 
                try {
                    const serverUrl = key._serverUrl; 
                    let mRes;
                    try { mRes = await axiosClient.get(`${serverUrl}/metrics/transfer`); } 
                    catch(err) { continue; }
                    const usage = mRes.data.bytesTransferredByUserId[key.id] || 0; 
                    const limit = key.dataLimit ? key.dataLimit.bytes : 0; 
                    let expireDateStr = null; 
                    if (key.name.includes('|')) expireDateStr = key.name.split('|').pop().trim(); 
                    const isTrial = key.name.startsWith("TEST_"); 
                    const expiredStatus = isExpired(expireDateStr); 
                    
                    if (key.name.startsWith("🔴")) {
                        if (limit !== 0) { await axiosClient.put(`${serverUrl}/access-keys/${key.id}/data-limit`, { limit: { bytes: 0 } }); }
                        continue; 
                    }

                    if (isTrial && (expiredStatus || (limit > 0 && usage >= limit))) { 
                        await axiosClient.delete(`${serverUrl}/access-keys/${key.id}`); 
                        const reason = expiredStatus ? "Trial Expired" : "Trial Data Limit"; 
                        ADMIN_IDS.forEach(aid => bot.sendMessage(aid, `🗑️ **TRIAL DELETED**\n\n👤 Name: ${sanitizeText(key.name)}\n⚠️ Reason: ${reason}`, {parse_mode: 'Markdown'})); 
                        continue; 
                    } 

                    if (!isTrial) {
                        if (expiredStatus) {
                            const expireMoment = moment.tz(expireDateStr, "YYYY-MM-DD", "Asia/Yangon").startOf('day');
                            const daysPast = today.diff(expireMoment, 'days');
                            if (daysPast >= 20) {
                                await axiosClient.delete(`${serverUrl}/access-keys/${key.id}`);
                                ADMIN_IDS.forEach(aid => bot.sendMessage(aid, `🗑️ **AUTO DELETED (>20 Days)**\n\n👤 Name: ${sanitizeText(key.name)}\n📅 Expired: ${expireDateStr}`, {parse_mode: 'Markdown'}));
                                continue;
                            } 
                            const newName = `🔴 [BLOCKED] ${key.name}`;
                            await axiosClient.put(`${serverUrl}/access-keys/${key.id}/name`, { name: newName });
                            await axiosClient.put(`${serverUrl}/access-keys/${key.id}/data-limit`, { limit: { bytes: 0 } });
                            ADMIN_IDS.forEach(aid => bot.sendMessage(aid, `🚫 **AUTO BLOCKED (Expired)**\n\n👤 Name: ${sanitizeText(key.name)}\n📉 Limit: 0 Bytes`, {parse_mode: 'Markdown'}));
                            continue;
                        }
                        if (limit > 5000 && usage >= limit) { 
                            const newName = `🔴 [BLOCKED] ${key.name}`;
                            await axiosClient.put(`${serverUrl}/access-keys/${key.id}/name`, { name: newName });
                            await axiosClient.put(`${serverUrl}/access-keys/${key.id}/data-limit`, { limit: { bytes: 0 } });
                            if (!blockedRegistry[key.id]) { 
                                blockedRegistry[key.id] = now; 
                                fs.writeFileSync(BLOCKED_FILE, JSON.stringify(blockedRegistry)); 
                                // Calculate display usage for alert
                                const { displayUsed } = getDisplayData(key.id, usage, limit);
                                const msg = `🚫 **AUTO BLOCKED (Data Full)**\n\n👤 Name: ${sanitizeText(key.name)}\n⬇️ Used: ${formatBytes(displayUsed)}`; 
                                ADMIN_IDS.forEach(aid => bot.sendMessage(aid, msg, {parse_mode: 'Markdown'})); 
                            } 
                        } 
                    }
                } catch (innerError) { continue; }
            } 
        } catch (e) { console.log("Guardian Error", e.message); } 
        finally { isGuardianRunning = false; }
    }
    // Set Interval to 20 Seconds
    setInterval(runGuardian, 20000); 
}
EOF

# 7. Install Node Modules
echo -e "${YELLOW}Installing Node Modules...${NC}"
cd /root/vpn-shop
cat << 'PKG' > package.json
{
  "name": "vpn-shop",
  "version": "1.0.0",
  "description": "Outline Telegram Bot & Panel",
  "main": "bot.js",
  "scripts": {
    "start": "node bot.js"
  },
  "dependencies": {
    "axios": "^1.6.0",
    "body-parser": "^1.20.2",
    "cors": "^2.8.5",
    "express": "^4.18.2",
    "moment-timezone": "^0.5.43",
    "node-telegram-bot-api": "^0.63.0"
  }
}
PKG
npm install

# 8. Setup Nginx (Backend Proxy only - No Webpanel files)
echo -e "${YELLOW}Configuring Nginx (Backend Proxy)...${NC}"
cat << 'NGINX' > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name _;
    
    # We remove the root /var/www/html since you don't want Webpanel
    # Instead, we just proxy API requests or show a simple status
    
    location /api/ {
        proxy_pass http://localhost:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    location / {
        return 200 'VPN Bot is Running!';
        add_header Content-Type text/plain;
    }
}
NGINX
systemctl reload nginx

# 9. Setup Firewall (UFW)
if ufw status | grep -q "Status: active"; then
    echo -e "${YELLOW}Configuring Firewall...${NC}"
    ufw allow 80/tcp
    ufw allow 3000/tcp
fi

# 10. Start Bot with PM2
echo -e "${YELLOW}Starting Bot Process...${NC}"
npm install -g pm2
pm2 start bot.js --name "vpn-shop"
pm2 startup
pm2 save

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN} INSTALLATION COMPLETE! (With Backup Logic) ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "Backend Port: ${YELLOW}3000${NC}"
echo -e "Service Name: ${YELLOW}vpn-shop${NC}"
echo -e "Status: Bot is running with Backup/Restore & Reset Logic."
