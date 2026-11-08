# ၁။ သင့်ရဲ့ Bot Token ကို ဒီနေရာမှာ ထည့်ပါ (ဥပမာ - "123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ")
BOT_TOKEN="8462905533:AAHzw3hyoyed6ahLLWN7HF0blXmod0llRlc"

# ၂။ PM2 နှင့် နောက်ကွယ်က Node Process အားလုံးကို ရပ်ပစ်ခြင်း
pm2 delete all
pkill -f node

# ၃။ Telegram ဆာဗာပေါ်ရှိ Webhook နှင့် ပိတ်မိနေသော Updates များကို ရှင်းလင်းခြင်း
echo " đang ရှင်းလင်းနေသည် Telegram Webhook..."
curl -s "https://api.telegram.org/bot${BOT_TOKEN}/deleteWebhook?drop_pending_updates=true"
echo -e "\nWebhook cleared successfully!"

# ၄။ Connection Lock ပြေလည်ရန် ၃ စက္ကန့် စောင့်ဆိုင်းခြင်း
sleep 3

# ၅။ IPv4 Flag ဖြင့် PM2 တွင် Bot ကို ပြန်လည်စတင်ခြင်း 
# (မှတ်ချက် - သင့် Main file နာမည်က index.js ဖြစ်သည်၊ တကယ်လို့ အခြားဖြစ်ရင် index.js နေရာမှာ ပြောင်းပေးပါ)
pm2 start index.js --name "vpn-shop" --node-args="--dns-result-order=ipv4first"
pm2 save

echo "----------------------------------------"
echo "Bot restarted! Showing live logs below:"
echo "----------------------------------------"

# ၆။ Live Logs များကို စစ်ဆေးရန်
pm2 logs vpn-shop --lines 20
