#!/bin/bash

# အရောင်များ
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

clear
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN} 🚀 VPN SHOP BOT INSTALLER (MYANMAR TIME)  ${NC}"
echo -e "${GREEN}===========================================${NC}"

# --- 1. Bot & Server Config ---
echo -e "${CYAN}--- [1/3] SERVER CONFIGURATION ---${NC}"
read -p "1. Enter Telegram Bot Token: " BOT_TOKEN
echo -e "${YELLOW}⚠️  Note: API URL must start with 'https://' and end with secret key.${NC}"
read -p "2. Enter Outline API URL: " API_URL
read -p "3. Enter Admin Telegram ID (Numeric only): " ADMIN_ID
read -p "4. Enter Admin Username (e.g. @admin): " ADMIN_USERNAME

echo -e ""
# --- 2. Payment Configuration ---
echo -e "${CYAN}--- [2/3] PAYMENT DETAILS ---${NC}"
read -p "1. Kpay Phone Number: " KPAY_NUM
read -p "   Kpay Account Name: " KPAY_NAME
read -p "2. Wave Phone Number: " WAVE_NUM
read -p "   Wave Account Name: " WAVE_NAME

echo -e ""
# --- 3. Plan Customization ---
echo -e "${CYAN}--- [3/3] PLAN CUSTOMIZATION ---${NC}"

# PLAN 1
echo -e "\n${GREEN}👉 Plan 1 Settings:${NC}"
read -p "   GB Amount (e.g., 10): " P1_GB
read -p "   Duration Days (e.g., 30): " P1_DAYS
read -p "   Price (e.g., 3000 MMK): " P1_PRICE

# PLAN 2
echo -e "\n${GREEN}👉 Plan 2 Settings:${NC}"
read -p "   GB Amount (e.g., 30): " P2_GB
read -p "   Duration Days (e.g., 30): " P2_DAYS
read -p "   Price (e.g., 7000 MMK): " P2_PRICE

# PLAN 3
echo -e "\n${GREEN}👉 Plan 3 Settings:${NC}"
read -p "   GB Amount (e.g., 50): " P3_GB
read -p "   Duration Days (e.g., 999): " P3_DAYS
read -p "   Price (e.g., 12000 MMK): " P3_PRICE

# Set Defaults
P1_GB=${P1_GB:-10}; P1_DAYS=${P1_DAYS:-30}; P1_PRICE=${P1_PRICE:-3,000 MMK}
P2_GB=${P2_GB:-30}; P2_DAYS=${P2_DAYS:-30}; P2_PRICE=${P2_PRICE:-7,000 MMK}
P3_GB=${P3_GB:-50}; P3_DAYS=${P3_DAYS:-999}; P3_PRICE=${P3_PRICE:-12,000 MMK}

# ---------------------------------------------------------
# SYSTEM SETUP
# ---------------------------------------------------------
echo -e "\n${YELLOW}🔄 Updating System & Installing Node.js...${NC}"
apt update && apt upgrade -y
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
apt install -y nodejs

echo -e "${YELLOW}📁 Setting up Project Folder...${NC}"
rm -rf /root/vpn-shop
mkdir -p /root/vpn-shop
cd /root/vpn-shop

echo -e "${YELLOW}📦 Installing Libraries...${NC}"
npm init -y > /dev/null 2>&1
npm install axios node-telegram-bot-api pm2 -g
npm install pm2 -g

# ---------------------------------------------------------
# GENERATING BOT.JS
# ---------------------------------------------------------
echo -e "${YELLOW}📝 Generating bot.js...${NC}"

touch bot.js
cat > bot.js <<'END_OF_FILE'
const axios = require('axios');
const https = require('https');
const TelegramBot = require('node-telegram-bot-api');
const fs = require('fs');

// ================================================================
// ⚠️ CONFIGURATION
// ================================================================
const OUTLINE_API_URL = "REPLACE_API_URL"; 
const TELEGRAM_TOKEN = "REPLACE_BOT_TOKEN"; 
const ADMIN_ID = REPLACE_ADMIN_ID; 

const AUTO_DELETE_HOURS = 24; 
const TEST_PLAN = { days: 1, gb: 1 }; 

const PLANS = {
    'plan_1': { name: 'REPLACE_P1_DAYS Days - REPLACE_P1_GB GB', days: REPLACE_P1_DAYS, gb: REPLACE_P1_GB, price: 'REPLACE_P1_PRICE' },
    'plan_2': { name: 'REPLACE_P2_DAYS Days - REPLACE_P2_GB GB', days: REPLACE_P2_DAYS, gb: REPLACE_P2_GB, price: 'REPLACE_P2_PRICE' },
    'plan_3': { name: 'REPLACE_P3_DAYS Days - REPLACE_P3_GB GB', days: REPLACE_P3_DAYS, gb: REPLACE_P3_GB, price: 'REPLACE_P3_PRICE' }
};

const PAYMENT_INFO = `
💸 **Payment Methods:**
1️⃣ Kpay: REPLACE_KPAY_NUM (REPLACE_KPAY_NAME)
2️⃣ Wave: REPLACE_WAVE_NUM (REPLACE_WAVE_NAME)

⚠️ ငွေလွှဲပြီးပါက ပြေစာ (Screenshot) ပို့ပေးပါ။
`;

const CHECK_INTERVAL = 10000; 
// ================================================================

const agent = new https.Agent({ rejectUnauthorized: false, keepAlive: true });
const client = axios.create({ httpsAgent: agent, timeout: 30000, headers: { 'Content-Type': 'application/json' } });
const bot = new TelegramBot(TELEGRAM_TOKEN, { polling: true });

const userStates = {}; 
let blockedKeys = {}; 
const CLAIM_FILE = 'claimed_users.json';
let claimedUsers = [];
if (fs.existsSync(CLAIM_FILE)) { try { claimedUsers = JSON.parse(fs.readFileSync(CLAIM_FILE)); } catch(e) {} }

// --- HELPERS (MYANMAR TIME) ---
function formatBytes(bytes) {
    if (!bytes || bytes === 0) return '0 B';
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return (bytes / Math.pow(1024, i)).toFixed(2) + ' ' + ['B', 'KB', 'MB', 'GB', 'TB'][i];
}

// 🔥 Myanmar Time (YYYY-MM-DD)
function getMyanmarDate(offsetDays = 0) {
    const date = new Date();
    date.setDate(date.getDate() + parseInt(offsetDays));
    return date.toLocaleDateString('en-CA', { timeZone: 'Asia/Yangon' });
}

function getDaysRemaining(dateString) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateString)) return "Unknown";
    const todayStr = getMyanmarDate(0); // Use Myanmar Today
    const today = new Date(todayStr);
    const target = new Date(dateString);
    const diffTime = target - today;
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    return diffDays > 0 ? `${diffDays} Days` : "Expired";
}

function getProgressBar(used, total) {
    if (total === 0) return "ERROR";
    const percentage = Math.min((used / total) * 100, 100);
    const totalLength = 10; 
    const filledLength = Math.round((percentage / 100) * totalLength);
    const bar = '█'.repeat(filledLength) + '░'.repeat(totalLength - filledLength);
    return `[${bar}] ${percentage.toFixed(1)}%`;
}

// ================================================================
// 🎨 MAIN MENU LAYOUT
// ================================================================
const mainMenuKeyboard = {
    reply_markup: {
        keyboard: [
            [{ text: "🆓 အစမ်း Key (1GB)(1Day)" }, { text: "🛒 VPN Key ဝယ်ရန်" }],
            [{ text: "👤 Package စစ်ရန်" }, { text: "🆘 ဆက်သွယ်ရန်" }]
        ],
        resize_keyboard: true,
        one_time_keyboard: false
    }
};

// 🤖 COMMANDS & MENU HANDLERS
bot.onText(/\/start/, (msg) => {
    const userId = msg.chat.id;
    console.log(`[DEBUG] User ID: ${userId} | Admin ID Configured: ${ADMIN_ID}`);

    if (String(userId) === String(ADMIN_ID)) {
        bot.sendMessage(userId, "👮‍♂️ **Admin Detected**\nUse /admin to open panel.", { parse_mode: 'Markdown' });
    }

    bot.sendMessage(userId, "👋 မင်္ဂလာပါ VPN Shop မှ ကြိုဆိုပါတယ်။\nမိမိလိုအပ်သော ဝန်ဆောင်မှုကို အောက်တွင် ရွေးချယ်နိုင်ပါသည်။", mainMenuKeyboard);
});

// Admin Panel Command
bot.onText(/\/admin/, (msg) => {
    if (String(msg.chat.id) === String(ADMIN_ID)) {
        const opts = {
            reply_markup: {
                inline_keyboard: [
                    [{ text: "👥 User List", callback_data: 'admin_list_users' }],
                    [{ text: "📊 Check Server", callback_data: 'check_status' }]
                ]
            }
        };
        bot.sendMessage(msg.chat.id, "👮‍♂️ **Admin Control Panel**", opts);
    }
});

// --- MENU BUTTON LOGIC MAPPING ---

// 1. FREE TEST KEY
bot.onText(/^(🆓 အစမ်း Key \(1GB\)\(1Day\))$/, async (msg) => {
    const chatId = msg.chat.id;
    const userFirstName = msg.from.first_name;

    if (claimedUsers.includes(chatId)) { 
        return bot.sendMessage(chatId, "⚠️ **Sorry!**\nမိတ်ဆွေ Test Key ထုတ်ယူပြီးသား ဖြစ်ပါသည်။\nPremium Plan ကို ဝယ်ယူအသုံးပြုပေးပါ။", { parse_mode: 'Markdown' }); 
    }
    
    bot.sendMessage(chatId, "⏳ Creating Test Key...");
    try {
        const expireDate = getMyanmarDate(TEST_PLAN.days); // Use MM Time
        const name = `TEST_${userFirstName.replace(/\|/g, '').trim()} | ${expireDate}`;
        const limit = TEST_PLAN.gb * 1024 * 1024 * 1024;
        const res = await client.post(`${OUTLINE_API_URL}/access-keys`);
        await client.put(`${OUTLINE_API_URL}/access-keys/${res.data.id}/name`, { name });
        await client.put(`${OUTLINE_API_URL}/access-keys/${res.data.id}/data-limit`, { limit: { bytes: limit } });
        claimedUsers.push(chatId); fs.writeFileSync(CLAIM_FILE, JSON.stringify(claimedUsers));
        bot.sendMessage(chatId, `🎉 **Free Trial Created!**\n\n👤 Name: ${userFirstName}\n📦 Limit: 1 GB\n📅 Expire: 1 Day\n\n🔗 **Key:**\n\`${res.data.accessUrl}\``, { parse_mode: 'Markdown' });
    } catch (e) { bot.sendMessage(chatId, "❌ Error creating test key."); }
});

// 2. BUY PREMIUM KEY
bot.onText(/^(🛒 VPN Key ဝယ်ရန်)$/, (msg) => {
    const keyboard = Object.keys(PLANS).map(key => [{ text: `${PLANS[key].name} - ${PLANS[key].price}`, callback_data: `select_${key}_NEW_0` }]);
    bot.sendMessage(msg.chat.id, "📅 **မိမိဝယ်ယူလိုသော Plan ကို ရွေးချယ်ပါ:**", { parse_mode: 'Markdown', reply_markup: { inline_keyboard: keyboard } });
});

// 3. MY ACCOUNT
bot.onText(/^(👤 Package စစ်ရန်)$/, async (msg) => {
    bot.sendMessage(msg.chat.id, "🔎 Checking Account Status...");
    await checkUserStatus(msg.chat.id, msg.from.first_name);
});

// 4. CONTACT ADMIN
bot.onText(/^(🆘 ဆက်သွယ်ရန်)$/, (msg) => {
    bot.sendMessage(msg.chat.id, "🆘 Admin သို့ တိုက်ရိုက်ဆက်သွယ်ရန် အောက်ပါခလုတ်ကို နှိပ်ပါ။", {
        reply_markup: { inline_keyboard: [[{ text: "💬 Chat with Admin", url: `https://t.me/REPLACE_ADMIN_USER` }]] }
    });
});

// 🤖 CALLBACK QUERY
bot.on('callback_query', async (callbackQuery) => {
    const msg = callbackQuery.message;
    const chatId = msg.chat.id;
    const data = callbackQuery.data;
    const userFirstName = callbackQuery.from.first_name;

    // (Inline button version of Test Key)
    if (data === 'get_test_key') {
        if (claimedUsers.includes(chatId)) { return bot.sendMessage(chatId, "⚠️ **Sorry!**\nမိတ်ဆွေ Test Key ထုတ်ယူပြီးသား ဖြစ်ပါသည်။"); }
        bot.sendMessage(chatId, "⏳ Creating Test Key...");
        try {
            const expireDate = getMyanmarDate(TEST_PLAN.days); // Use MM Time
            const name = `TEST_${userFirstName.replace(/\|/g, '').trim()} | ${expireDate}`;
            const limit = TEST_PLAN.gb * 1024 * 1024 * 1024;
            const res = await client.post(`${OUTLINE_API_URL}/access-keys`);
            await client.put(`${OUTLINE_API_URL}/access-keys/${res.data.id}/name`, { name });
            await client.put(`${OUTLINE_API_URL}/access-keys/${res.data.id}/data-limit`, { limit: { bytes: limit } });
            claimedUsers.push(chatId); fs.writeFileSync(CLAIM_FILE, JSON.stringify(claimedUsers));
            bot.sendMessage(chatId, `🎉 **Free Trial Created!**\n\n👤 Name: ${userFirstName}\n📦 Limit: 1 GB\n📅 Expire: 1 Day\n\n🔗 **Key:**\n\`${res.data.accessUrl}\``, { parse_mode: 'Markdown' });
        } catch (e) { bot.sendMessage(chatId, "❌ Error."); }
        return;
    }

    if (data === 'check_status') { bot.sendMessage(chatId, "🔎 Checking..."); await checkUserStatus(chatId, userFirstName); }

    if (data.startsWith('select_')) {
        const realPlanKey = data.match(/plan_\d+/)[0]; 
        const realType = data.includes('RENEW') ? 'RENEW' : 'NEW';
        const realKeyId = data.split('_').pop();
        userStates[chatId] = { status: 'WAITING_SLIP', plan: PLANS[realPlanKey], name: userFirstName, type: realType, renewKeyId: realKeyId };
        bot.sendMessage(chatId, `✅ **Selected:** ${PLANS[realPlanKey].name}\n💰 **Price:** ${PLANS[realPlanKey].price}\n\n${PAYMENT_INFO}`, { parse_mode: 'Markdown' });
    }

    if (data.startsWith('renew_start_')) {
        const keyIdToRenew = data.split('_')[2];
        const keyboard = Object.keys(PLANS).map(key => [{ text: `${PLANS[key].name} - ${PLANS[key].price}`, callback_data: `select_${key}_RENEW_${keyIdToRenew}` }]);
        bot.sendMessage(chatId, "🔄 **Renew လုပ်မည့် Plan ကို ရွေးချယ်ပါ:**", { parse_mode: 'Markdown', reply_markup: { inline_keyboard: keyboard } });
    }

    if (String(chatId) === String(ADMIN_ID)) {
        if (data === 'admin_list_users') await sendUserList(chatId);
        if (data.startsWith('approve_')) {
            const buyerId = data.split('_')[1];
            if (userStates[buyerId]) {
                const { plan, name, type, renewKeyId } = userStates[buyerId];
                bot.editMessageCaption("✅ Approved", { chat_id: ADMIN_ID, message_id: msg.message_id });
                let resultKey;
                if (type === 'RENEW') resultKey = await renewKeyForUser(renewKeyId, plan, name);
                else resultKey = await createKeyForUser(buyerId, plan, name);
                if (resultKey) {
                    bot.sendMessage(buyerId, `🎉 **Success!**\n\n👤 Name: ${name}\n📅 Expire: ${resultKey.expireDate}\n\n🔗 **Key:**\n\`${resultKey.accessUrl}\``, { parse_mode: 'Markdown' });
                    delete userStates[buyerId];
                }
            }
        }
        if (data.startsWith('confirm_delete_')) {
            const keyId = data.split('_')[2];
            bot.sendMessage(chatId, `⚠️ Delete Key ID: ${keyId}?`, { reply_markup: { inline_keyboard: [[{ text: "✅ YES", callback_data: `do_delete_${keyId}` }, { text: "❌ NO", callback_data: `cancel_delete` }]] } });
        }
        if (data.startsWith('do_delete_')) { await client.delete(`${OUTLINE_API_URL}/access-keys/${data.split('_')[2]}`); bot.sendMessage(chatId, "✅ Deleted."); }
        if (data === 'cancel_delete') bot.deleteMessage(chatId, msg.message_id);
        if (data.startsWith('reject_')) { bot.sendMessage(data.split('_')[1], "❌ Rejected."); bot.editMessageCaption("❌ Rejected", { chat_id: ADMIN_ID, message_id: msg.message_id }); }
    }
});

bot.on('photo', async (msg) => {
    const chatId = msg.chat.id;
    if (userStates[chatId] && userStates[chatId].status === 'WAITING_SLIP') {
        const { plan, name, type } = userStates[chatId];
        bot.sendMessage(chatId, "📩 Slip Received.");
        bot.sendPhoto(ADMIN_ID, msg.photo[msg.photo.length - 1].file_id, {
            caption: `💰 Order: ${name} | ${plan.name}\nType: ${type === 'RENEW' ? '🔄 RENEW' : '🛒 NEW'}`,
            reply_markup: { inline_keyboard: [[{ text: "✅ Approve", callback_data: `approve_${chatId}` }, { text: "❌ Reject", callback_data: `reject_${chatId}` }]] }
        });
    }
});
bot.onText(/\/manage[ _](.+)/, async (msg, match) => { if (String(msg.chat.id) === String(ADMIN_ID)) await sendKeyDetails(msg.chat.id, match[1].trim()); });

// --- CORE FUNCTIONS (USER VIEW) ---
async function checkUserStatus(chatId, firstName) {
    try {
        const [kRes, mRes] = await Promise.all([client.get(`${OUTLINE_API_URL}/access-keys`), client.get(`${OUTLINE_API_URL}/metrics/transfer`)]);
        const myKey = kRes.data.accessKeys.find(k => k.name.includes(firstName));
        
        if (!myKey) return bot.sendMessage(chatId, "❌ **Account Not Found**\n(Name mismatch? Contact Admin)");
        
        const used = mRes.data.bytesTransferredByUserId[myKey.id] || 0;
        const limit = myKey.dataLimit ? myKey.dataLimit.bytes : 0;
        const remaining = limit - used;
        
        let cleanName = myKey.name; let expireDate = "Unknown";
        if (myKey.name.includes('|')) { const parts = myKey.name.split('|'); cleanName = parts[0].trim(); expireDate = parts[1].trim(); }

        // Sanitize Name
        cleanName = cleanName.replace(/[_*\[\]()~`>#+\-=|{}.!]/g, " ");

        let status = "🟢 Active";
        let isBlocked = false;
        if (limit > 0 && remaining <= 0) { status = "🔴 Data Depleted"; isBlocked = true; }
        if (limit <= 5000) { status = "🔴 Expired/Blocked"; isBlocked = true; }
        if (myKey.name.startsWith("TEST_")) status += " (TRIAL)";

        const remainingDays = getDaysRemaining(expireDate);

        const msg = `
👤 **Name:** ${cleanName}
📡 **Status:** ${status}
⏳ **Remaining Day:** ${remainingDays}
⬇️ **Used:** ${formatBytes(used)}
🎁 **Remaining Data:** ${formatBytes(remaining > 0 ? remaining : 0)}
📅 **Expire:** ${expireDate}

${getProgressBar(used, limit)}
`;
        const opts = { parse_mode: 'Markdown' };
        if (limit <= 5000 && !myKey.name.startsWith("TEST_")) opts.reply_markup = { inline_keyboard: [[{ text: "🔄 RENEW KEY NOW", callback_data: `renew_start_${myKey.id}` }]] };
        else if (limit <= 5000 && myKey.name.startsWith("TEST_")) opts.reply_markup = { inline_keyboard: [[{ text: "🛒 Upgrade to Premium", callback_data: `buy_vpn` }]] };
        
        bot.sendMessage(chatId, msg, opts);
    } catch (e) { 
        console.error(e);
        bot.sendMessage(chatId, "⚠️ Server Error."); 
    }
}

async function createKeyForUser(userId, plan, userName) {
    try {
        const expireDate = getMyanmarDate(plan.days); // Use MM Time
        const name = `${userName.replace(/\|/g, '').trim()} | ${expireDate}`;
        const limit = plan.gb * 1024 * 1024 * 1024;
        const res = await client.post(`${OUTLINE_API_URL}/access-keys`);
        await client.put(`${OUTLINE_API_URL}/access-keys/${res.data.id}/name`, { name });
        await client.put(`${OUTLINE_API_URL}/access-keys/${res.data.id}/data-limit`, { limit: { bytes: limit } });
        return { accessUrl: res.data.accessUrl, expireDate };
    } catch (e) { return null; }
}

async function renewKeyForUser(keyId, plan, userName) {
    try {
        const expireDate = getMyanmarDate(plan.days); // Use MM Time
        const cleanName = userName.replace('TEST_', '').replace(/\|/g, '').trim();
        const name = `${cleanName} | ${expireDate}`;
        const limit = plan.gb * 1024 * 1024 * 1024;
        await client.put(`${OUTLINE_API_URL}/access-keys/${keyId}/name`, { name });
        await client.put(`${OUTLINE_API_URL}/access-keys/${keyId}/data-limit`, { limit: { bytes: limit } });
        if (blockedKeys[keyId]) delete blockedKeys[keyId];
        const res = await client.get(`${OUTLINE_API_URL}/access-keys`);
        const key = res.data.accessKeys.find(k => String(k.id) === String(keyId));
        return { accessUrl: key.accessUrl, expireDate };
    } catch (e) { return null; }
}

async function sendUserList(chatId) { 
    bot.sendMessage(chatId, "⏳ Connecting to Server...");
    try {
        const res = await client.get(`${OUTLINE_API_URL}/access-keys`);
        let message = "👥 **User List**\n\n";
        res.data.accessKeys.forEach(k => { message += `🆔 \`${k.id}\` : ${k.name}\n👉 /manage_${k.id}\n\n`; });
        bot.sendMessage(chatId, message, { parse_mode: 'Markdown' });
    } catch (e) {
        bot.sendMessage(chatId, `❌ **API Error!**\n\n${e.message}`);
    }
}

async function sendKeyDetails(chatId, keyId) {
    try {
        const [keysRes, metricsRes] = await Promise.all([client.get(`${OUTLINE_API_URL}/access-keys`), client.get(`${OUTLINE_API_URL}/metrics/transfer`)]);
        const key = keysRes.data.accessKeys.find(k => String(k.id) === String(keyId));
        if (!key) return bot.sendMessage(chatId, "❌ Key not found.");

        const usage = metricsRes.data.bytesTransferredByUserId[key.id] || 0;
        const limit = key.dataLimit ? key.dataLimit.bytes : 0;
        const remaining = limit - usage;
        
        let cleanName = key.name; let expireDate = "Unknown";
        if (key.name.includes('|')) { const parts = key.name.split('|'); cleanName = parts[0].trim(); expireDate = parts[1].trim(); }

        let status = "🟢 Active";
        if (limit > 0 && remaining <= 0) status = "🔴 Data Depleted";
        if (limit <= 5000) status = "🔴 Expired/Blocked";

        const remainingDays = getDaysRemaining(expireDate);

        const msg = `
👮‍♂️ **User Management**
-----------------------
👤 **Name:** ${cleanName}
📡 **Status:** ${status}
⏳ **Remaining Day:** ${remainingDays}
⬇️ **Used:** ${formatBytes(usage)}
🎁 **Remaining Data:** ${formatBytes(remaining > 0 ? remaining : 0)}
📅 **Expire:** ${expireDate}

${getProgressBar(usage, limit)}
`;
        bot.sendMessage(chatId, msg, { parse_mode: 'Markdown', reply_markup: { inline_keyboard: [[{ text: "🗑️ DELETE", callback_data: `confirm_delete_${key.id}` }]] } });
    } catch (e) {
        bot.sendMessage(chatId, `❌ **Error:** ${e.message}`);
    }
}

async function runGuardian() {
    try {
        const [kRes, mRes] = await Promise.all([client.get(`${OUTLINE_API_URL}/access-keys`), client.get(`${OUTLINE_API_URL}/metrics/transfer`)]);
        const keys = kRes.data.accessKeys;
        const usage = mRes.data.bytesTransferredByUserId || {};
        const today = getMyanmarDate(0); // Use MM Time
        const now = Date.now();
        for (const k of keys) {
            const lim = k.dataLimit ? k.dataLimit.bytes : 0;
            const isTestKey = k.name.startsWith("TEST_");
            if (isTestKey) {
                let testExpired = false;
                if (k.name.includes('|')) { const d = k.name.split('|')[1].trim(); if (/^\d{4}-\d{2}-\d{2}$/.test(d) && d < today) testExpired = true; }
                if (lim > 0 && (usage[k.id] || 0) >= lim) testExpired = true;
                if (testExpired) { await client.delete(`${OUTLINE_API_URL}/access-keys/${k.id}`); continue; }
            }
            if (!isTestKey) {
                if (lim > 0 && lim <= 5000) {
                    if (!blockedKeys[k.id]) { blockedKeys[k.id] = now; } 
                    else { if ((now - blockedKeys[k.id]) / (3600000) >= AUTO_DELETE_HOURS) { try { await client.delete(`${OUTLINE_API_URL}/access-keys/${k.id}`); delete blockedKeys[k.id]; bot.sendMessage(ADMIN_ID, `🗑️ **Auto-Deleted:** ${k.name}`); } catch (err) {} } }
                    continue;
                }
                let block = false;
                if (k.name.includes('|')) { const d = k.name.split('|')[1].trim(); if (/^\d{4}-\d{2}-\d{2}$/.test(d) && d < today) block = true; }
                if (lim > 5000 && (usage[k.id] || 0) >= lim) block = true;
                if (block) { await client.put(`${OUTLINE_API_URL}/access-keys/${k.id}/data-limit`, { limit: { bytes: 1 } }); blockedKeys[k.id] = now; bot.sendMessage(ADMIN_ID, `🚫 **Blocked:** ${k.name}\n⏳ Will delete in 24h.`); }
            }
        }
    } catch (e) { console.error("Guardian Error"); }
}
runGuardian();
setInterval(runGuardian, CHECK_INTERVAL);
console.log("🚀 Bot Started with Updated Label!");
END_OF_FILE

# ---------------------------------------------------------
# APPLY CONFIGURATION
# ---------------------------------------------------------
echo -e "${YELLOW}⚙️ Applying Configurations...${NC}"

# Replace Server Config
sed -i "s|REPLACE_API_URL|$API_URL|g" bot.js
sed -i "s|REPLACE_BOT_TOKEN|$BOT_TOKEN|g" bot.js
sed -i "s|REPLACE_ADMIN_ID|$ADMIN_ID|g" bot.js

# Fix Admin Username (Remove @ if exists)
CLEAN_USERNAME=${ADMIN_USERNAME//@/}
sed -i "s|REPLACE_ADMIN_USER|$CLEAN_USERNAME|g" bot.js

# Replace Payment Config
sed -i "s|REPLACE_KPAY_NUM|$KPAY_NUM|g" bot.js
sed -i "s|REPLACE_KPAY_NAME|$KPAY_NAME|g" bot.js
sed -i "s|REPLACE_WAVE_NUM|$WAVE_NUM|g" bot.js
sed -i "s|REPLACE_WAVE_NAME|$WAVE_NAME|g" bot.js

# Replace Plan Configs
sed -i "s|REPLACE_P1_GB|$P1_GB|g" bot.js; sed -i "s|REPLACE_P1_DAYS|$P1_DAYS|g" bot.js; sed -i "s|REPLACE_P1_PRICE|$P1_PRICE|g" bot.js
sed -i "s|REPLACE_P2_GB|$P2_GB|g" bot.js; sed -i "s|REPLACE_P2_DAYS|$P2_DAYS|g" bot.js; sed -i "s|REPLACE_P2_PRICE|$P2_PRICE|g" bot.js
sed -i "s|REPLACE_P3_GB|$P3_GB|g" bot.js; sed -i "s|REPLACE_P3_DAYS|$P3_DAYS|g" bot.js; sed -i "s|REPLACE_P3_PRICE|$P3_PRICE|g" bot.js

# ---------------------------------------------------------
# START BOT
# ---------------------------------------------------------
echo -e "${GREEN}🚀 Stopping old process...${NC}"
pm2 delete vpn-shop > /dev/null 2>&1

echo -e "${GREEN}🚀 Starting Bot...${NC}"
pm2 start bot.js --name "vpn-shop"
pm2 save
pm2 startup

echo -e "\n${GREEN}✅ INSTALLATION SUCCESSFUL!${NC}"
echo -e "${YELLOW}Your VPN Shop Bot is running with Myanmar Time!${NC}"
