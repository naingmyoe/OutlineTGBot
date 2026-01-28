#!/bin/bash

# 3xbot Ultimate Installer (v9.2 - Traffic Stats Fix)
# Updates:
# 1. FIXED: Traffic fetch method (Now uses 'clientStats' object).
# 2. FIXED: Solves the "0 B" issue by merging live stats with user settings.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=====================================================${NC}"
echo -e "${CYAN}    3xbot Installer v9.2 (Real Traffic Fix)          ${NC}"
echo -e "${CYAN}=====================================================${NC}"

# Check Root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}[Error] Please run as root (sudo -i)${NC}"
  exit 1
fi

# Check Node.js
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

# Setup Directory
PROJECT_DIR="/root/3xbot"
mkdir -p "$PROJECT_DIR/public"
cd "$PROJECT_DIR"

# 1. Create package.json
cat > package.json <<EOF
{
  "name": "3xbot-manager",
  "version": "9.2.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "body-parser": "^1.20.2",
    "node-telegram-bot-api": "^0.64.0",
    "axios": "^1.6.0",
    "uuid": "^9.0.1",
    "moment": "^2.29.4",
    "child_process": "^1.0.2"
  }
}
EOF

# 2. Config Template
if [ ! -f config.json ]; then
    cat << 'EOF' > config.json
{
  "telegram": {
    "token": "",
    "adminId": 0,
    "adminUsername": "",
    "texts": {
        "buyBtn": "🛒 Buy Key",
        "freeBtn": "🎁 Free Trial",
        "resellerBtn": "🤝 Reseller Login",
        "contactBtn": "🆘 Contact Admin",
        "adminBtn": "👮 Admin Panel",
        "resBalance": "💰 Balance",
        "resCreate": "➕ Create Key",
        "resExtend": "👥 Extend User",
        "resLogout": "🚪 Logout"
    }
  },
  "trial": { "enabled": true, "limitGB": 1, "days": 1 },
  "protocols": {
    "vless": true,
    "vmess": true,
    "ss": true
  },
  "allUsers": [],
  "trialUsers": [],
  "servers": [],
  "plans": [],
  "resellers": [],
  "resellerPlans": [],
  "activeSessions": []
}
EOF
fi

# 3. Create index.js (UPDATED: clientStats Logic)
cat > index.js <<'EOF'
const express = require('express');
const bodyParser = require('body-parser');
const TelegramBot = require('node-telegram-bot-api');
const axios = require('axios');
const fs = require('fs');
const path = require('path');
const cors = require('cors');
const moment = require('moment');
const { exec } = require('child_process');
const { v4: uuidv4 } = require('uuid');

const app = express();
const PORT = 3000; 
const configPath = path.join(__dirname, 'config.json');

app.use(cors());
app.use(bodyParser.json());
app.use(express.static('public'));

// State Management
let pendingOrders = {}; 
let resellerSessions = {}; 
let adminSession = {}; 
let bot = null; 

// --- HELPER FUNCTIONS ---
function loadConfig() { 
    try { 
        let cfg = JSON.parse(fs.readFileSync(configPath));
        if(!cfg.allUsers) cfg.allUsers = []; 
        if(!cfg.activeSessions) cfg.activeSessions = [];
        if(!cfg.protocols) cfg.protocols = { vless: true, vmess: true, ss: true };
        return cfg; 
    } catch(e) { return {}; }
}
function saveConfig(data) { 
    fs.writeFileSync(configPath, JSON.stringify(data, null, 2)); 
}
function formatBytes(bytes, decimals = 2) {
    if (!+bytes) return '0 B';
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${parseFloat((bytes / Math.pow(k, i)).toFixed(dm))} ${sizes[i]}`;
}
function createProgressBar(current, total, size = 10) {
    const percent = total > 0 ? Math.min(Math.max(current / total, 0), 1) : 0;
    const filled = Math.round(size * percent);
    const empty = size - filled;
    return '▓'.repeat(filled) + '░'.repeat(empty) + ` ${Math.round(percent * 100)}%`;
}

// --- WEB API ---
app.get('/api/config', (req, res) => res.json(loadConfig()));
app.post('/api/config', (req, res) => {
    saveConfig(req.body);
    res.json({ success: true });
});
app.listen(PORT, () => console.log(`✅ Web Panel running on Port ${PORT}`));

// --- BOT LOGIC ---
let config = loadConfig();
if (config.telegram && config.telegram.token && config.telegram.token.length > 10) {
    startBot(config.telegram.token.trim());
}

function startBot(token) {
    bot = new TelegramBot(token, { polling: true });
    console.log("✅ Telegram Bot Started...");

    // Monitoring Loop (Every 60 Minutes)
    setInterval(() => {
        monitorExpirations();
    }, 60 * 60 * 1000); 

    const isAdmin = (chatId) => {
        const cfg = loadConfig();
        return String(cfg.telegram.adminId) === String(chatId) || (cfg.telegram.admins && cfg.telegram.admins.some(a => String(a.id) === String(chatId)));
    };

    const sendMainMenu = (chatId) => {
        const cfg = loadConfig();
        const txt = cfg.telegram.texts;
        let keyboard = [[{ text: txt.buyBtn }, { text: txt.freeBtn }], [{ text: txt.resellerBtn }, { text: txt.contactBtn }]];
        if (isAdmin(chatId)) keyboard.push([{ text: txt.adminBtn }]);
        bot.sendMessage(chatId, "👋 **Main Menu**", { parse_mode: 'Markdown', reply_markup: { keyboard, resize_keyboard: true } });
    };

    const sendAdminMenu = (chatId) => {
        const kb = [[{ text: "📢 Broadcast Message" }, { text: "👥 Reseller User" }], [{ text: "💰 Reseller TopUp" }, { text: "🖥 Server List" }], [{ text: "🔙 Back to Main Menu" }]];
        bot.sendMessage(chatId, "👮 **Admin Panel**", { parse_mode: 'Markdown', reply_markup: { keyboard: kb, resize_keyboard: true } });
    };

    bot.onText(/\/start/, (msg) => {
        const chatId = msg.chat.id;
        const cfg = loadConfig();
        if (!cfg.allUsers.includes(chatId)) { cfg.allUsers.push(chatId); saveConfig(cfg); }
        delete resellerSessions[chatId];
        delete adminSession[chatId];
        sendMainMenu(chatId);
    });

    bot.on('message', async (msg) => {
        const chatId = msg.chat.id;
        const text = msg.text;
        const currentCfg = loadConfig();
        const txt = currentCfg.telegram.texts;
        
        if (!text && !msg.photo) return;

        if (text === txt.buyBtn) {
            const btns = currentCfg.servers.map((s, i) => [{ text: `🌍 ${s.name}`, callback_data: `srv_${i}` }]);
            if(btns.length === 0) return bot.sendMessage(chatId, "⚠️ No servers configured.");
            return bot.sendMessage(chatId, "Step 1: Choose Server 👇", { reply_markup: { inline_keyboard: btns }});
        }
        if (text === txt.freeBtn) {
            if (!currentCfg.trial || !currentCfg.trial.enabled) return bot.sendMessage(chatId, "❌ Trial is currently disabled.");
            if (currentCfg.trialUsers.includes(chatId)) return bot.sendMessage(chatId, "❌ You have already used the trial.");
            const btns = currentCfg.servers.map((s, i) => [{ text: `🌍 ${s.name}`, callback_data: `trysrv_${i}` }]);
            return bot.sendMessage(chatId, "🆓 Trial Server 👇", { reply_markup: { inline_keyboard: btns }});
        }
        if (text === txt.contactBtn) {
            let adminListMsg = "🆘 **Admin Contact List**\n\n";
            if(currentCfg.telegram.adminUsername) adminListMsg += `1. @${currentCfg.telegram.adminUsername}\n`;
            if (currentCfg.telegram.admins) currentCfg.telegram.admins.forEach((admin, i) => { adminListMsg += `${i+2}. @${admin.username.replace('@','')}\n`; });
            return bot.sendMessage(chatId, adminListMsg, { parse_mode: 'Markdown' });
        }
        if (text === txt.resellerBtn) {
            resellerSessions[chatId] = { state: 'WAIT_USER' };
            return bot.sendMessage(chatId, "🔐 **Reseller Login**\nUsername:", {parse_mode: 'Markdown', reply_markup: { remove_keyboard: true }});
        }
        if (text === txt.adminBtn && isAdmin(chatId)) { sendAdminMenu(chatId); return; }

        // --- SLIP HANDLING ---
        if (msg.photo && pendingOrders[chatId]) {
            const order = pendingOrders[chatId];
            const plan = currentCfg.plans[order.planIdx];
            const pCode = order.proto === 'vmess' ? 'm' : (order.proto === 'ss' ? 's' : 'v');
            let pName = "VLESS";
            if(order.proto === 'vmess') pName = "VMess";
            if(order.proto === 'ss') pName = "Shadowsocks";

            bot.sendMessage(chatId, "⏳ **Slip Received!** Waiting approval...", {parse_mode: 'Markdown'});
            
            const uniqueAdmins = new Set();
            if(currentCfg.telegram.adminId) uniqueAdmins.add(String(currentCfg.telegram.adminId));
            if(currentCfg.telegram.admins) currentCfg.telegram.admins.forEach(a => uniqueAdmins.add(String(a.id)));

            const adminMsgLog = [];
            const caption = `🛒 **New Order**
👤 Name: ${msg.from.first_name} ${msg.from.last_name || ''}
🔗 Username: @${msg.from.username || 'None'}
📦 Order: ${plan.name}
🔌 Protocol: ${pName}
⏳ Days: ${plan.days} Days
📡 GB: ${plan.limitGB} GB
💰 Price: ${plan.price} MMK`;

            for (const adminId of uniqueAdmins) {
                try {
                    const sentMsg = await bot.sendPhoto(adminId, msg.photo[msg.photo.length-1].file_id, {
                        caption: caption,
                        reply_markup: { inline_keyboard: [[{ text: "✅ Approve", callback_data: `app_${chatId}_${order.srvIdx}_${pCode}_${order.planIdx}` }, { text: "❌ Reject", callback_data: `rej_${chatId}` }]]} 
                    });
                    adminMsgLog.push({ adminId: adminId, msgId: sentMsg.message_id });
                } catch(e) {}
            }
            pendingOrders[chatId].adminMsgs = adminMsgLog; 
        }

        // --- ADMIN / RESELLER SESSIONS ---
        if (isAdmin(chatId)) {
            if (text === "🔙 Back to Main Menu") { delete adminSession[chatId]; sendMainMenu(chatId); return; }
            if (text === "📢 Broadcast Message") { adminSession[chatId] = { state: 'WAIT_BROADCAST' }; return bot.sendMessage(chatId, "📢 Send message."); }
            if (adminSession[chatId]?.state === 'WAIT_BROADCAST') {
                const users = currentCfg.allUsers || [];
                bot.sendMessage(chatId, `🚀 Sending...`);
                users.forEach(uid => { try { if (msg.photo) bot.sendPhoto(uid, msg.photo[msg.photo.length-1].file_id, { caption: msg.caption }); else bot.sendMessage(uid, text); } catch(e) {} });
                delete adminSession[chatId]; return;
            }
            if (text === "👥 Reseller User") { if (currentCfg.resellers.length === 0) return bot.sendMessage(chatId, "⚠️ No resellers."); handleAdminResellerList(chatId); return; }
            if (text === "💰 Reseller TopUp") {
                const btns = currentCfg.resellers.map((r, i) => [{ text: `${r.username} (${r.balance})`, callback_data: `admtop_${i}` }]);
                return bot.sendMessage(chatId, "💰 Select Reseller:", { reply_markup: { inline_keyboard: btns } });
            }
            if (adminSession[chatId]?.state === 'WAIT_TOPUP_AMOUNT') {
                const amount = parseInt(text); if (!amount) return bot.sendMessage(chatId, "❌ Invalid.");
                const resIdx = adminSession[chatId].resIdx; currentCfg.resellers[resIdx].balance += amount; saveConfig(currentCfg); delete adminSession[chatId];
                return bot.sendMessage(chatId, `✅ Added **${amount}**.`);
            }
            if (text === "🖥 Server List") {
                const btns = currentCfg.servers.map((s, i) => [{ text: `🖥 ${s.name}`, callback_data: `admsrv_${i}` }]);
                return bot.sendMessage(chatId, "🖥 **Select a Server:**", { parse_mode: 'Markdown', reply_markup: { inline_keyboard: btns } });
            }
        }

        if (resellerSessions[chatId]?.state === 'WAIT_USER') { resellerSessions[chatId].username = text; resellerSessions[chatId].state = 'WAIT_PASS'; return bot.sendMessage(chatId, "🔑 Password:"); }
        if (resellerSessions[chatId]?.state === 'WAIT_PASS') {
            const r = currentCfg.resellers.find(x => x.username === resellerSessions[chatId].username && x.password === text);
            if (r) { resellerSessions[chatId].state = 'LOGGED_IN'; showResellerMenu(chatId, r.username); } 
            else { delete resellerSessions[chatId]; bot.sendMessage(chatId, "❌ Failed."); sendMainMenu(chatId); }
            return;
        }
        if (resellerSessions[chatId]?.state === 'WAIT_KEY_NAME') {
            const keyName = text.replace(/[^a-zA-Z0-9 ]/g, "").trim(); if (keyName.length < 2) return bot.sendMessage(chatId, "⚠️ Name too short.");
            const temp = resellerSessions[chatId].tempOrder; const resIdx = currentCfg.resellers.findIndex(r => r.username === resellerSessions[chatId].username); const plan = currentCfg.resellerPlans[temp.planIdx];
            if (currentCfg.resellers[resIdx].balance < plan.price) { resellerSessions[chatId].state = 'LOGGED_IN'; return bot.sendMessage(chatId, "❌ Insufficient Balance."); }
            currentCfg.resellers[resIdx].balance -= plan.price; saveConfig(currentCfg);
            bot.sendMessage(chatId, `✅ **${plan.name}** Purchased!`, {parse_mode: 'Markdown'});
            await generateResellerKey(chatId, currentCfg.servers[temp.srvIdx], plan, temp.proto, resIdx, keyName);
            resellerSessions[chatId].state = 'LOGGED_IN'; delete resellerSessions[chatId].tempOrder; showResellerMenu(chatId, resellerSessions[chatId].username); return;
        }
        if (resellerSessions[chatId]?.state === 'LOGGED_IN') {
             if (text === txt.resCreate) { handleResellerCreate(chatId); return; }
             if (text === txt.resExtend) { 
                 const rIdx = currentCfg.resellers.findIndex(r => r.username === resellerSessions[chatId].username);
                 handleResellerList(chatId, rIdx, 0); 
                 return; 
             }
             if (text === txt.resLogout) { delete resellerSessions[chatId]; sendMainMenu(chatId); return; }
             if (text.startsWith(txt.resBalance)) { showResellerMenu(chatId, resellerSessions[chatId].username); return; }
        }
    });

    bot.on('callback_query', async (query) => {
        const chatId = query.message.chat.id;
        const data = query.data;
        const currentCfg = loadConfig();
        const pCfg = currentCfg.protocols || { vless: true, vmess: true, ss: true };

        if (data.startsWith('srv_') || data.startsWith('rsrv_') || data.startsWith('trysrv_')) {
             const mode = data.split('_')[0]; 
             const srvIdx = data.split('_')[1];
             const protoPrefix = mode === 'srv' ? 'proto' : (mode === 'rsrv' ? 'rproto' : 'tryproto');
             
             const protoBtns = [];
             if (pCfg.vless) protoBtns.push([{ text: "VLESS", callback_data: `${protoPrefix}_${srvIdx}_vless` }]);
             if (pCfg.vmess) protoBtns.push([{ text: "VMess", callback_data: `${protoPrefix}_${srvIdx}_vmess` }]);
             if (pCfg.ss) protoBtns.push([{ text: "Shadowsocks", callback_data: `${protoPrefix}_${srvIdx}_ss` }]);

             if(protoBtns.length === 0) return bot.answerCallbackQuery(query.id, { text: "⚠️ No protocols enabled by Admin.", show_alert: true });

             bot.editMessageText("Select Protocol:", { chat_id: chatId, message_id: query.message.message_id, reply_markup: { inline_keyboard: protoBtns }});
        }

        if (data.startsWith('proto_')) {
             const [_, srvIdx, proto] = data.split('_');
             const planBtns = currentCfg.plans.map((p, idx) => [{ text: `${p.days}Days ${p.limitGB}GB ${p.price}MMK`, callback_data: `plan_${srvIdx}_${proto}_${idx}` }]);
             bot.editMessageText("Select Plan:", { chat_id: chatId, message_id: query.message.message_id, reply_markup: { inline_keyboard: planBtns }});
        }
        if (data.startsWith('rproto_')) { 
            const [_, srvIdx, proto] = data.split('_');
            const planBtns = currentCfg.resellerPlans.map((p, idx) => [{ text: `${p.days}Days ${p.limitGB}GB ${p.price}MMK`, callback_data: `rplan_${srvIdx}_${proto}_${idx}` }]);
            bot.editMessageText("Select Reseller Plan:", { chat_id: chatId, message_id: query.message.message_id, reply_markup: { inline_keyboard: planBtns }});
        }
        if (data.startsWith('tryproto_')) {
             const [_, srvIdx, proto] = data.split('_');
             const fresh = loadConfig();
             if(fresh.trialUsers.includes(chatId)) return bot.sendMessage(chatId, "⚠️ Trial used.");
             fresh.trialUsers.push(chatId); saveConfig(fresh);
             await generateAndSendKey(chatId, fresh.servers[srvIdx], {name: "Trial", limitGB: fresh.trial.limitGB, days: fresh.trial.days}, proto, true);
        }

        if (data.startsWith('plan_')) {
             const [_, srvIdx, proto, planIdx] = data.split('_');
             pendingOrders[chatId] = { srvIdx, proto, planIdx };
             const plan = currentCfg.plans[planIdx];
             const msgText = `✅ **Selected**
⏳ Days: ${plan.days} Days
📡 GB: ${plan.limitGB} GB
💰 Price: ${plan.price} MMK

❗️ **Please upload payment slip.**`;
             bot.sendMessage(chatId, msgText, {parse_mode: 'Markdown'});
        }
        if (data.startsWith('rplan_')) { 
            const [_, srvIdx, proto, planIdx] = data.split('_');
            resellerSessions[chatId].tempOrder = { srvIdx, proto, planIdx };
            resellerSessions[chatId].state = 'WAIT_KEY_NAME';
            bot.deleteMessage(chatId, query.message.message_id);
            bot.sendMessage(chatId, "👤 **Enter Name for User:**", {parse_mode: 'Markdown'});
        }

        if (data.startsWith('app_')) {
            const [_, uId, srv, pCode, pIdx] = data.split('_');
            const order = pendingOrders[uId];
            if (order && order.adminMsgs) {
                const adminName = query.from.first_name;
                order.adminMsgs.forEach(log => { bot.editMessageCaption(`✅ **Approved by ${adminName}**`, { chat_id: log.adminId, message_id: log.msgId, parse_mode: 'Markdown' }).catch(()=>{}); });
                let proto = pCode==='m'?'vmess':(pCode==='s'?'ss':'vless');
                bot.sendMessage(uId, "✅ Payment Approved! Generating...");
                await generateAndSendKey(uId, currentCfg.servers[srv], currentCfg.plans[pIdx], proto, false);
                delete pendingOrders[uId];
            } else bot.answerCallbackQuery(query.id, {text: "Expired/Processed", show_alert: true});
        }
        if (data.startsWith('rej_')) {
            const uId = data.split('_')[1];
            const order = pendingOrders[uId];
            if (order && order.adminMsgs) {
                const adminName = query.from.first_name;
                order.adminMsgs.forEach(log => { bot.editMessageCaption(`❌ **Rejected by ${adminName}**`, { chat_id: log.adminId, message_id: log.msgId, parse_mode: 'Markdown' }).catch(()=>{}); });
                bot.sendMessage(uId, "❌ Payment Rejected.");
                delete pendingOrders[uId];
            }
        }

        if (data.startsWith('admsrv_')) { await fetchAndShowServerUsers(chatId, parseInt(data.split('_')[1]), 0, query.message.message_id); }
        if (data.startsWith('srvpage_')) { 
            if (!adminSession[chatId] || adminSession[chatId].type !== 'SERVER_VIEW') {
                 return bot.answerCallbackQuery(query.id, { text: "⚠️ Session Expired. Please click 'Server List' again.", show_alert: true });
            }
            await renderServerUserPage(chatId, parseInt(data.split('_')[1]), query.message.message_id); 
        }

        if (data.startsWith('admviewres_')) { await handleAdminResellerUserList(chatId, parseInt(data.split('_')[1]), 0); }
        if (data.startsWith('admu_page_')) { const [_, resIdx, page] = data.split('_'); await handleAdminResellerUserList(chatId, parseInt(resIdx), parseInt(page), query.message.message_id); }
        if (data.startsWith('admshowu_')) { const [_, resIdx, userIdx] = data.split('_'); await showAdminResellerUserDetails(chatId, resIdx, userIdx); }
        if (data.startsWith('admren_')) {
            const [_, resIdx, userIdx] = data.split('_');
            const planBtns = currentCfg.resellerPlans.map((p, idx) => [{ text: `${p.days}Days ${p.limitGB}GB ${p.price}K`, callback_data: `admdoren_${resIdx}_${userIdx}_${idx}` }]);
            planBtns.push([{text: "🔙 Back", callback_data: `admshowu_${resIdx}_${userIdx}`}]);
            bot.editMessageText("👮 **Admin Renew:**", { chat_id: chatId, message_id: query.message.message_id, reply_markup: { inline_keyboard: planBtns }, parse_mode: 'Markdown' });
        }
        if (data.startsWith('admdoren_')) {
            const [_, resIdx, userIdx, planIdx] = data.split('_');
            const plan = currentCfg.resellerPlans[planIdx];
            await renewResellerUser(chatId, resIdx, userIdx, plan.price, plan.days, plan.limitGB, true);
        }
        if (data.startsWith('admdel_')) {
            const [_, resIdx, userIdx] = data.split('_');
            await deleteResellerUser(chatId, resIdx, userIdx, true, query.message.message_id);
        }
        if (data.startsWith('admtop_')) {
            const resIdx = data.split('_')[1];
            adminSession[chatId] = { state: 'WAIT_TOPUP_AMOUNT', resIdx: resIdx };
            bot.editMessageText(`💰 TopUp for **${currentCfg.resellers[resIdx].username}**\nEnter Amount:`, { chat_id: chatId, message_id: query.message.message_id });
        }
        
        if (data.startsWith('rpage_')) {
            const [_, resIdxStr, pageStr] = data.split('_');
            await handleResellerList(chatId, parseInt(resIdxStr), parseInt(pageStr), query.message.message_id);
        }
        if (data.startsWith('rview_')) { 
            const [_, resIdx, userIdx] = data.split('_');
            await showResellerUserDetails(chatId, resIdx, userIdx);
        }
        if (data.startsWith('rshowren_')) {
            const [_, resIdx, userIdx] = data.split('_');
            const planBtns = currentCfg.resellerPlans.map((p, idx) => [{ text: `${p.days}Days ${p.limitGB}GB ${p.price}MMK`, callback_data: `rdoren_${resIdx}_${userIdx}_${idx}` }]);
            planBtns.push([{text: "🔙 Back", callback_data: `rview_${resIdx}_${userIdx}`}]);
            bot.editMessageText("⏳ **Select Plan:**", { chat_id: chatId, message_id: query.message.message_id, reply_markup: { inline_keyboard: planBtns }, parse_mode: 'Markdown' });
        }
        if (data.startsWith('rdoren_')) {
            const [_, resIdx, userIdx, planIdx] = data.split('_');
            const plan = currentCfg.resellerPlans[planIdx];
            if (currentCfg.resellers[resIdx].balance < plan.price) return bot.answerCallbackQuery(query.id, { text: "❌ Insufficient Balance!", show_alert: true });
            await renewResellerUser(chatId, resIdx, userIdx, plan.price, plan.days, plan.limitGB);
            showResellerMenu(chatId, resellerSessions[chatId].username);
        }
        if (data.startsWith('rdel_')) { 
            const [_, resIdx, userIdx] = data.split('_');
            await deleteResellerUser(chatId, resIdx, userIdx, false, query.message.message_id);
        }
    });
}

// --- SHARED FUNCTIONS ---

// 1. Monitor Expiration with Stats Fix
async function monitorExpirations() {
    const cfg = loadConfig();
    console.log("⏰ Checking expirations...");
    
    if (!cfg.activeSessions || cfg.activeSessions.length === 0) return;

    let updated = false;

    for (let sIdx = 0; sIdx < cfg.servers.length; sIdx++) {
        const srv = cfg.servers[sIdx];
        try {
            const cookies = await login(srv);
            if (!cookies) continue;
            
            const res = await axios.get(`${srv.url}/panel/api/inbounds/list`, { headers: { 'Cookie': cookies } });
            if (!res.data || !res.data.success) continue;

            const inbounds = res.data.obj;
            let serverClients = [];

            // Updated Logic: Merge Settings with clientStats
            inbounds.forEach(inb => {
                const settings = JSON.parse(inb.settings);
                const clientStats = inb.clientStats || []; // Capture live stats

                if (settings.clients) {
                    settings.clients.forEach(c => {
                        // Find matching stat for this client email
                        const stat = clientStats.find(s => s.email === c.email);
                        const liveUp = stat ? stat.up : (c.up || 0);
                        const liveDown = stat ? stat.down : (c.down || 0);
                        
                        // Push merged object
                        serverClients.push({
                            ...c,
                            up: liveUp,
                            down: liveDown
                        });
                    });
                }
            });

            for (let i = 0; i < cfg.activeSessions.length; i++) {
                const session = cfg.activeSessions[i];
                if (session.serverIdx !== sIdx) continue; 
                if (session.notified) continue; 

                const clientData = serverClients.find(c => c.email === session.email);
                if (clientData) {
                    const totalUsed = Number(clientData.up) + Number(clientData.down);
                    const isExpired = clientData.expiryTime > 0 && clientData.expiryTime <= Date.now();
                    const isDataFull = clientData.totalGB > 0 && totalUsed >= clientData.totalGB;

                    if (isExpired || isDataFull) {
                        const reason = isExpired ? "📅 Plan Expired" : "📉 Data Limit Reached";
                        try {
                            await bot.sendMessage(session.chatId, `⚠️ **System Alert**\n\nUser: ${session.email}\nReason: ${reason}\n\nPlease renew your plan.`, { parse_mode: 'Markdown' });
                            session.notified = true; 
                            updated = true;
                        } catch (e) {}
                    }
                }
            }
        } catch (e) {
            console.log(`Monitor Error: ${e.message}`);
        }
    }
    
    if (updated) saveConfig(cfg);
}

function showResellerMenu(chatId, username) {
    const freshCfg = loadConfig(); const txt = freshCfg.telegram.texts;
    const reseller = freshCfg.resellers.find(r => r.username === username);
    const balance = reseller ? reseller.balance : 0;
    const kb = [[{ text: `${txt.resBalance}: ${balance} MMK` }], [{ text: txt.resCreate }, { text: txt.resExtend }], [{ text: txt.resLogout }]];
    bot.sendMessage(chatId, `👤 **Reseller Dashboard**\nUser: ${username}`, { parse_mode: 'Markdown', reply_markup: { keyboard: kb, resize_keyboard: true } });
}
function handleResellerCreate(chatId) {
    const config = loadConfig();
    const btns = config.servers.map((s, i) => [{ text: `🌍 ${s.name}`, callback_data: `rsrv_${i}` }]);
    bot.sendMessage(chatId, "Select Server:", { reply_markup: { inline_keyboard: btns } });
}

async function handleResellerList(chatId, resIdx, page, msgIdToEdit = null) {
    const config = loadConfig();
    const reseller = config.resellers[resIdx];
    
    if (!reseller) {
        if(msgIdToEdit) bot.deleteMessage(chatId, msgIdToEdit);
        return bot.sendMessage(chatId, "⚠️ Session Expired. Please login again.");
    }

    if (!reseller.createdUsers || reseller.createdUsers.length === 0) {
        return bot.sendMessage(chatId, "⚠️ No users created yet.");
    }

    const pageSize = 10; 
    const totalUsers = reseller.createdUsers.length; 
    const totalPages = Math.ceil(totalUsers / pageSize); 
    const start = page * pageSize; 
    const currentUsers = reseller.createdUsers.slice(start, start + pageSize);
    
    const btns = currentUsers.map((u, i) => [{ text: `[${config.servers[u.serverIdx]?.name||'?'}] ${u.name}`, callback_data: `rview_${resIdx}_${start + i}` }]);
    
    const navRow = [];
    if (page > 0) navRow.push({ text: "⬅️", callback_data: `rpage_${resIdx}_${page - 1}` });
    if (page < totalPages - 1) navRow.push({ text: "➡️", callback_data: `rpage_${resIdx}_${page + 1}` });
    
    if (navRow.length > 0) btns.push(navRow);
    const text = `👥 **User Management (${page + 1}/${totalPages})**`;
    
    if (msgIdToEdit) {
        try {
            await bot.editMessageText(text, { chat_id: chatId, message_id: msgIdToEdit, parse_mode: 'Markdown', reply_markup: { inline_keyboard: btns } });
        } catch(e) {}
    } else {
        bot.sendMessage(chatId, text, { parse_mode: 'Markdown', reply_markup: { inline_keyboard: btns } });
    }
}

// 2. Fix Reseller Details View (Uses clientStats)
async function showResellerUserDetails(chatId, resIdxStr, userIdxStr) {
    const config = loadConfig(); const resIdx = parseInt(resIdxStr); const userIdx = parseInt(userIdxStr);
    const reseller = config.resellers[resIdx]; const u = reseller.createdUsers[userIdx]; const server = config.servers[u.serverIdx];
    bot.sendMessage(chatId, "🔄 Details...", { parse_mode: 'Markdown' });
    try {
        const cookies = await login(server);
        if(!cookies) return bot.sendMessage(chatId, "❌ Server Error");
        const inboundRes = await axios.get(`${server.url}/panel/api/inbounds/get/${u.inboundId}`, { headers: { 'Cookie': cookies } });
        if(inboundRes.data && inboundRes.data.success) {
            const inboundObj = inboundRes.data.obj;
            const settings = JSON.parse(inboundObj.settings);
            const clientStats = inboundObj.clientStats || []; // Grab Stats

            const client = settings.clients.find(c => c.email === u.email);
            if(client) {
                 // ** FIX: Look for live stats **
                 const stat = clientStats.find(s => s.email === u.email);
                 const liveUp = stat ? Number(stat.up) : Number(client.up||0);
                 const liveDown = stat ? Number(stat.down) : Number(client.down||0);
                 const totalUsed = liveUp + liveDown;

                 const daysLeft = client.expiryTime > 0 ? Math.ceil((client.expiryTime - Date.now()) / 86400000) : 0;
                 const usedStr = formatBytes(totalUsed); 
                 const freeStr = formatBytes(client.totalGB - totalUsed);
                 const expStr = moment(client.expiryTime).format("YYYY-MM-DD");
                 const status = client.enable ? "🟢 Active" : "🔴 Disabled";
                 const protocolName = inboundObj.protocol === 'vmess' ? 'VMess' : (inboundObj.protocol === 'vless' ? 'VLESS' : 'Shadowsocks');
                 const msg = `👮 **User Management**
-------------------------
👤 Name: ${u.name}
🖥 Server: ${server.name}
🔌 Protocol: ${protocolName}
📡 Status: ${status}
⏳ Remaining: ${daysLeft} Days
📊 Used: ${usedStr}
🎁 Free: ${freeStr}
📅 Expire: ${expStr}

${createProgressBar(totalUsed, client.totalGB)}`;
                 const btns = [[{ text: "⏳ RENEW", callback_data: `rshowren_${resIdx}_${userIdx}` }], [{ text: "🗑 DELETE", callback_data: `rdel_${resIdx}_${userIdx}` }]];
                 await bot.sendMessage(chatId, msg, { parse_mode: 'Markdown', reply_markup: { inline_keyboard: btns } });
            } else bot.sendMessage(chatId, "❌ User deleted.");
        }
    } catch(e) { bot.sendMessage(chatId, "❌ Error."); }
}

// 3. Fix Admin User Details (Uses clientStats)
async function showAdminResellerUserDetails(chatId, resIdxStr, userIdxStr) {
    const config = loadConfig(); const resIdx = parseInt(resIdxStr); const userIdx = parseInt(userIdxStr);
    const reseller = config.resellers[resIdx]; const u = reseller.createdUsers[userIdx]; const server = config.servers[u.serverIdx];
    try {
        const cookies = await login(server); const inboundRes = await axios.get(`${server.url}/panel/api/inbounds/get/${u.inboundId}`, { headers: { 'Cookie': cookies } });
        const inboundObj = inboundRes.data.obj;
        const settings = JSON.parse(inboundObj.settings); 
        const clientStats = inboundObj.clientStats || [];

        const client = settings.clients.find(c => c.email === u.email);
        
        // ** FIX: Traffic calculation **
        const stat = clientStats.find(s => s.email === u.email);
        const liveUp = stat ? Number(stat.up) : Number(client.up||0);
        const liveDown = stat ? Number(stat.down) : Number(client.down||0);
        const totalUsed = liveUp + liveDown;
        
        const protocolName = inboundObj.protocol === 'vmess' ? 'VMess' : (inboundObj.protocol === 'vless' ? 'VLESS' : 'Shadowsocks');
        
        const msg = `👮 **Admin User Control**
-------------------------
👤 Name: ${u.name}
🖥 Server: ${server.name}
🔌 Protocol: ${protocolName}
📡 Status: ${client.enable?'🟢 Active':'🔴 Disabled'}
⏳ Left: ${Math.ceil((client.expiryTime-Date.now())/86400000)} Days
📊 Used: ${formatBytes(totalUsed)}
🎁 Free: ${formatBytes(client.totalGB - totalUsed)}
📅 Expire: ${moment(client.expiryTime).format("YYYY-MM-DD")}

${createProgressBar(totalUsed, client.totalGB)}`;
        const btns = [[{ text: "⏳ ADMIN RENEW", callback_data: `admren_${resIdx}_${userIdx}` }], [{ text: "🗑 ADMIN DELETE", callback_data: `admdel_${resIdx}_${userIdx}` }]];
        bot.sendMessage(chatId, msg, { parse_mode: 'Markdown', reply_markup: { inline_keyboard: btns } });
    } catch(e) { bot.sendMessage(chatId, "Error"); }
}

async function renewResellerUser(chatId, resIdxStr, userIdxStr, price, days, limitGB, isAdmin = false) {
    const cfg = loadConfig();
    const resIdx = parseInt(resIdxStr); const userIdx = parseInt(userIdxStr);
    const userRec = cfg.resellers[resIdx].createdUsers[userIdx];
    const srv = cfg.servers[userRec.serverIdx];
    const cookies = await login(srv); if(!cookies) return;
    try {
        try { await axios.post(`${srv.url}/panel/api/inbounds/resetClientTraffic/${userRec.inboundId}/${userRec.email}`, {}, { headers: { 'Cookie': cookies } }); } catch(e) {}
        const res = await axios.get(`${srv.url}/panel/api/inbounds/get/${userRec.inboundId}`, { headers: { 'Cookie': cookies } });
        const inbound = res.data.obj; const settings = JSON.parse(inbound.settings);
        const clientIdx = settings.clients.findIndex(c => c.email === userRec.email);
        const client = settings.clients[clientIdx];
        client.expiryTime = Date.now() + (days * 86400000); client.enable = true; client.up = 0; client.down = 0;
        if(limitGB) client.totalGB = limitGB * 1024 * 1024 * 1024;
        settings.clients[clientIdx] = client;
        await axios.post(`${srv.url}/panel/api/inbounds/update/${userRec.inboundId}`, { ...inbound, settings: JSON.stringify(settings) }, { headers: { 'Cookie': cookies } });
        cfg.resellers[resIdx].balance -= price; 
        
        const session = cfg.activeSessions.find(s => s.email === userRec.email);
        if(session) session.notified = false;

        saveConfig(cfg);
        const header = isAdmin ? "👮 Admin Renewed!" : "✅ Renewed!";
        bot.sendMessage(chatId, `${header}\nUser: ${userRec.name}\nActive: 🟢`);
    } catch(e) { bot.sendMessage(chatId, "❌ Error."); }
}
async function deleteResellerUser(chatId, resIdxStr, userIdxStr, isAdmin = false, msgIdToDelete = null) {
    const cfg = loadConfig();
    const resIdx = parseInt(resIdxStr); const userIdx = parseInt(userIdxStr);
    const userRec = cfg.resellers[resIdx].createdUsers[userIdx];
    const srv = cfg.servers[userRec.serverIdx];
    const cookies = await login(srv); if(!cookies) return;
    try {
        const res = await axios.get(`${srv.url}/panel/api/inbounds/get/${userRec.inboundId}`, { headers: { 'Cookie': cookies } });
        const inbound = res.data.obj; let settings = JSON.parse(inbound.settings);
        const initialCount = settings.clients.length;
        settings.clients = settings.clients.filter(c => c.email !== userRec.email);
        if(settings.clients.length < initialCount) await axios.post(`${srv.url}/panel/api/inbounds/update/${userRec.inboundId}`, { ...inbound, settings: JSON.stringify(settings) }, { headers: { 'Cookie': cookies } });
        
        cfg.resellers[resIdx].createdUsers.splice(userIdx, 1);
        cfg.activeSessions = cfg.activeSessions.filter(s => s.email !== userRec.email);
        saveConfig(cfg);

        if(msgIdToDelete) try { await bot.deleteMessage(chatId, msgIdToDelete); } catch(e){}
        const header = isAdmin ? "👮 **Admin Deleted User:**" : "🗑 **Deleted User:**";
        bot.sendMessage(chatId, `${header} ${userRec.name}`);
    } catch(e) { bot.sendMessage(chatId, "❌ Error."); }
}
async function login(server) { try { const res = await axios.post(`${server.url}/login`, { username: server.username, password: server.password }); return res.headers['set-cookie']; } catch (e) { return null; } }
async function generateResellerKey(chatId, srv, plan, protocol, resIdx, customName) {
    const uuid = uuidv4(); const cookies = await login(srv); if (!cookies) return bot.sendMessage(chatId, "❌ Error");
    let inboundId = protocol==='vmess'?srv.vmessId:(protocol==='ss'?srv.ssId:srv.vlessId);
    try {
        const email = `${customName}_${uuid.slice(0,4)}`; const remark = `R-${customName} (${plan.limitGB}GB)`;
        await axios.post(`${srv.url}/panel/api/inbounds/addClient`, { id: parseInt(inboundId), settings: JSON.stringify({ clients: [{ id: uuid, password: uuid, email: email, totalGB: plan.limitGB*1024*1024*1024, expiryTime: Date.now() + (plan.days*86400000), enable: true, flow: "" }] }) }, { headers: { 'Cookie': cookies } });
        const cfg = loadConfig();
        if(!cfg.resellers[resIdx].createdUsers) cfg.resellers[resIdx].createdUsers = [];
        cfg.resellers[resIdx].createdUsers.push({ name: customName, email: email, inboundId: inboundId, serverIdx: cfg.servers.findIndex(s=>s.url === srv.url), planPrice: plan.price, planDays: plan.days });
        
        if(!cfg.activeSessions) cfg.activeSessions = [];
        cfg.activeSessions.push({ email: email, chatId: chatId, serverIdx: cfg.servers.findIndex(s=>s.url === srv.url), notified: false });

        saveConfig(cfg);
        const res = await axios.get(`${srv.url}/panel/api/inbounds/get/${inboundId}`, { headers: { 'Cookie': cookies } });
        const inbound = res.data.obj; const settings = JSON.parse(inbound.settings); const client = settings.clients.find(c => c.email === email); const ip = srv.url.split('//')[1].split(':')[0]; const link = generateLink(protocol, inbound, client, ip, remark);
        bot.sendMessage(chatId, `✅ **Created!**\nName: ${customName}\n\n\`${link}\``, { parse_mode: 'Markdown' });
    } catch (e) { bot.sendMessage(chatId, "❌ Error."); }
}
async function generateAndSendKey(chatId, srv, plan, protocol, isTrial) {
    const uuid = uuidv4(); const cookies = await login(srv); if (!cookies) return bot.sendMessage(chatId, "❌ Error");
    let inboundId = protocol==='vmess'?srv.vmessId:(protocol==='ss'?srv.ssId:srv.vlessId);
    try {
        const userChat = await bot.getChat(chatId); const cleanName = (userChat.first_name||"User").replace(/[^a-zA-Z0-9 ]/g, "").trim(); const email = `${cleanName}_${Date.now().toString().slice(-4)}`; const remark = isTrial ? `Trial-${cleanName}` : `${cleanName} (${plan.limitGB}GB)`;
        await axios.post(`${srv.url}/panel/api/inbounds/addClient`, { id: parseInt(inboundId), settings: JSON.stringify({ clients: [{ id: uuid, password: uuid, email: email, totalGB: plan.limitGB*1024*1024*1024, expiryTime: Date.now() + (plan.days*86400000), enable: true, flow: "" }] }) }, { headers: { 'Cookie': cookies } });
        
        const cfg = loadConfig();
        if(!cfg.activeSessions) cfg.activeSessions = [];
        cfg.activeSessions.push({ email: email, chatId: chatId, serverIdx: cfg.servers.findIndex(s=>s.url === srv.url), notified: false });
        saveConfig(cfg);

        const res = await axios.get(`${srv.url}/panel/api/inbounds/get/${inboundId}`, { headers: { 'Cookie': cookies } });
        const inbound = res.data.obj; const settings = JSON.parse(inbound.settings); const client = settings.clients.find(c => c.email === email); const ip = srv.url.split('//')[1].split(':')[0]; const link = generateLink(protocol, inbound, client, ip, remark);
        bot.sendMessage(chatId, `✅ **Key Generated!**\n${link}`, {parse_mode:'Markdown'});
    } catch(e) { bot.sendMessage(chatId, "❌ Error"); }
}
function generateLink(type, inbound, client, ip, remark) {
    const port = inbound.port; const stream = JSON.parse(inbound.streamSettings); const net = stream.network; const sec = stream.security; const path = (net === 'ws') ? (stream.wsSettings?.path || '/') : (stream.grpcSettings?.serviceName || '');
    if (type === 'vless') { let sni = sec==='reality'?stream.realitySettings?.serverNames?.[0]:(sec==='tls'?stream.tlsSettings?.serverNames?.[0]:""); let pbk = stream.realitySettings?.publicKey||""; let fp = stream.realitySettings?.fingerprint||""; return `vless://${client.id}@${ip}:${port}?type=${net}&security=${sec}&path=${path}&sni=${sni}&fp=${fp}&pbk=${pbk}#${encodeURIComponent(remark)}`; }
    if (type === 'vmess') { const config = { v: "2", ps: remark, add: ip, port: port, id: client.id, aid: "0", scy: "auto", net: net, type: "none", host: "", path: path, tls: sec, sni: sec==='tls'?stream.tlsSettings?.serverNames?.[0]:"" }; return "vmess://" + Buffer.from(JSON.stringify(config)).toString('base64'); }
    if (type === 'ss') { const creds = Buffer.from(`${JSON.parse(inbound.settings).method}:${client.password}`).toString('base64'); return `ss://${creds}@${ip}:${port}#${encodeURIComponent(remark)}`; }
    return "Link Error";
}
function handleAdminResellerList(chatId) {
    const config = loadConfig();
    const btns = config.resellers.map((r, i) => [{ text: `👤 ${r.username} (💰 ${r.balance})`, callback_data: `admviewres_${i}` }]);
    bot.sendMessage(chatId, "Select Reseller:", { reply_markup: { inline_keyboard: btns } });
}
function handleAdminResellerUserList(chatId, resIdx, page, msgIdToEdit = null) {
    const config = loadConfig();
    const reseller = config.resellers[resIdx];
    if (!reseller || !reseller.createdUsers || reseller.createdUsers.length === 0) return bot.sendMessage(chatId, `⚠️ **${reseller.username}** has no users.`);
    const pageSize = 10; const totalUsers = reseller.createdUsers.length; const totalPages = Math.ceil(totalUsers / pageSize); const start = page * pageSize; const currentUsers = reseller.createdUsers.slice(start, start + pageSize);
    const btns = currentUsers.map((u, i) => [{ text: `👤 ${u.name}`, callback_data: `admshowu_${resIdx}_${start+i}` }]);
    const navRow = [];
    if (page > 0) navRow.push({ text: "⬅️", callback_data: `admu_page_${resIdx}_${page - 1}` });
    if (page < totalPages - 1) navRow.push({ text: "➡️", callback_data: `admu_page_${resIdx}_${page + 1}` });
    if (navRow.length > 0) btns.push(navRow);
    const text = `👥 **${reseller.username}'s Users (${page + 1}/${totalPages})**`;
    if (msgIdToEdit) bot.editMessageText(text, { chat_id: chatId, message_id: msgIdToEdit, parse_mode: 'Markdown', reply_markup: { inline_keyboard: btns } });
    else bot.sendMessage(chatId, text, { parse_mode: 'Markdown', reply_markup: { inline_keyboard: btns } });
}

// 4. Fix Server User List (Uses clientStats)
async function fetchAndShowServerUsers(chatId, srvIdx, page = 0, msgIdToEdit = null) {
    const config = loadConfig();
    const server = config.servers[srvIdx];
    if(!server) return bot.sendMessage(chatId, "❌ Server not found.");
    try {
        const cookies = await login(server);
        if(!cookies) return bot.sendMessage(chatId, "❌ Login failed.");
        const res = await axios.get(`${server.url}/panel/api/inbounds/list`, { headers: { 'Cookie': cookies } });
        if(res.data && res.data.success) {
            let allClients = [];
            res.data.obj.forEach(inb => {
                const settings = JSON.parse(inb.settings);
                const clientStats = inb.clientStats || []; // Capture stats
                
                if(settings.clients) {
                    settings.clients.forEach(c => {
                        const stat = clientStats.find(s => s.email === c.email);
                        const liveUp = stat ? Number(stat.up) : Number(c.up||0);
                        const liveDown = stat ? Number(stat.down) : Number(c.down||0);
                        
                        allClients.push({ 
                            ...c, 
                            up: liveUp,
                            down: liveDown,
                            inboundTag: inb.tag, 
                            inboundId: inb.id 
                        });
                    });
                }
            });
            adminSession[chatId] = { type: 'SERVER_VIEW', clients: allClients, srvName: server.name, srvIdx: srvIdx };
            await renderServerUserPage(chatId, page, msgIdToEdit);
        } else bot.sendMessage(chatId, "❌ Failed to fetch list.");
    } catch(e) { bot.sendMessage(chatId, "❌ Connection Error."); }
}
async function renderServerUserPage(chatId, page, msgIdToEdit = null) {
    const session = adminSession[chatId];
    if(!session || session.type !== 'SERVER_VIEW') return;
    const pageSize = 10;
    const totalUsers = session.clients.length;
    const totalPages = Math.ceil(totalUsers / pageSize);
    const start = page * pageSize;
    const end = start + pageSize;
    const currentUsers = session.clients.slice(start, end);
    let msg = `🖥 **Server:** ${session.srvName}\n👥 **Total Users:** ${totalUsers}\n📄 **Page:** ${page+1}/${totalPages || 1}\n\n`;
    currentUsers.forEach((c, i) => {
        const totalUsed = Number(c.up) + Number(c.down);
        const daysLeft = c.expiryTime > 0 ? Math.ceil((c.expiryTime - Date.now()) / 86400000) : 0;
        const icon = c.enable ? "🟢" : "🔴";
        msg += `${start+i+1}. ${icon} **${c.email||'No Email'}**\n   📊 ${formatBytes(totalUsed)} | ⏳ ${daysLeft} Days | 📅 ${moment(c.expiryTime).format("YYYY-MM-DD")}\n\n`;
    });
    const btns = [];
    const navRow = [];
    if (page > 0) navRow.push({ text: "⬅️ Prev", callback_data: `srvpage_${page - 1}` });
    if (page < totalPages - 1) navRow.push({ text: "Next ➡️", callback_data: `srvpage_${page + 1}` });
    if (navRow.length > 0) btns.push(navRow);
    if(msgIdToEdit) bot.editMessageText(msg, { chat_id: chatId, message_id: msgIdToEdit, parse_mode: 'Markdown', reply_markup: { inline_keyboard: btns } });
    else bot.sendMessage(chatId, msg, { parse_mode: 'Markdown', reply_markup: { inline_keyboard: btns } });
}
EOF

# 4. Install & Run
echo -e "${YELLOW}[INFO] Installing Dependencies...${NC}"
npm install
npm install -g pm2

echo -e "${YELLOW}[INFO] Starting System...${NC}"
pm2 delete 3xbot 2>/dev/null
pm2 start index.js --name "3xbot"
pm2 save
pm2 startup

IP=$(curl -s ifconfig.me)
echo -e "${GREEN}✅ UPDATE COMPLETE! (Real Traffic Fixed)${NC}"
echo -e "${GREEN}Panel: http://$IP:3000${NC}"
