#!/bin/bash

# ဖိုင်သိမ်းမည့် လမ်းကြောင်း
DIR="/root/3xbot/public"

# အရောင်များ
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}Creating directory at $DIR ...${NC}"

# 1. ဖိုင်တွဲ (Directory) တည်ဆောက်ခြင်း
mkdir -p "$DIR"

# 2. index.html ဖိုင်ကို ရေးသားထည့်သွင်းခြင်း (Updated Version)
echo -e "${GREEN}Writing updated index.html file...${NC}"

cat > "$DIR/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>3xbot Manager</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <style>
        body { background-color: #f0f2f5; font-family: 'Segoe UI', sans-serif; padding-bottom: 80px; }
        .header-title { color: #0d6efd; font-weight: 800; margin-top: 15px; text-align: center; }
        .custom-card { border: none; border-radius: 12px; background: white; box-shadow: 0 2px 5px rgba(0,0,0,0.05); margin-bottom: 15px; }
        .nav-pills .nav-link.active { background-color: #0d6efd; color: white; }
        .fab-container { position: fixed; bottom: 20px; right: 20px; z-index: 999; }
        .btn-fab { width: 60px; height: 60px; border-radius: 50%; font-size: 24px; display: flex; align-items: center; justify-content: center; box-shadow: 0 4px 15px rgba(0,0,0,0.3); }
        .server-header { cursor: pointer; background-color: #f8f9fa; padding: 12px 15px; }
        .card-body-custom { padding: 15px; }
        .form-label-sm { font-size: 11px; color: #666; font-weight: bold; text-transform: uppercase; }
        .form-switch .form-check-input { width: 2.5em; height: 1.25em; cursor: pointer; }
    </style>
</head>
<body>
<div class="container">
    <h4 class="header-title"><i class="fa-solid fa-robot"></i> 3xbot Panel</h4>
    <ul class="nav nav-pills justify-content-center my-3" id="pills-tab">
        <li class="nav-item"><button class="nav-link active" data-bs-toggle="pill" data-bs-target="#tab-bot">Bot</button></li>
        <li class="nav-item"><button class="nav-link" data-bs-toggle="pill" data-bs-target="#tab-server">Server</button></li>
        <li class="nav-item"><button class="nav-link" data-bs-toggle="pill" data-bs-target="#tab-plans">Plans</button></li>
        <li class="nav-item"><button class="nav-link" data-bs-toggle="pill" data-bs-target="#tab-reseller">Reseller</button></li>
    </ul>

    <div class="tab-content" id="pills-tabContent">
        <div class="tab-pane fade show active" id="tab-bot">
            <div class="custom-card card-body-custom">
                <h6 class="text-primary mb-3"><i class="fa-solid fa-network-wired"></i> Protocols</h6>
                <div class="row g-2">
                    <div class="col-4">
                        <div class="form-check form-switch">
                            <input class="form-check-input" type="checkbox" id="swVless">
                            <label class="form-check-label fw-bold">VLESS</label>
                        </div>
                    </div>
                    <div class="col-4">
                        <div class="form-check form-switch">
                            <input class="form-check-input" type="checkbox" id="swVmess">
                            <label class="form-check-label fw-bold">VMESS</label>
                        </div>
                    </div>
                    <div class="col-4">
                        <div class="form-check form-switch">
                            <input class="form-check-input" type="checkbox" id="swSS">
                            <label class="form-check-label fw-bold">Shadowsocks</label>
                        </div>
                    </div>
                </div>
            </div>

            <div class="custom-card card-body-custom">
                <div class="d-flex justify-content-between align-items-center mb-3">
                    <h6 class="text-primary m-0"><i class="fa-solid fa-gift"></i> Free Trial</h6>
                    <div class="form-check form-switch m-0">
                        <input class="form-check-input" type="checkbox" id="swTrial">
                    </div>
                </div>
                <div class="row g-2">
                    <div class="col-6">
                        <label class="form-label-sm">Quota (GB)</label>
                        <input type="number" id="trialGB" class="form-control" placeholder="1">
                    </div>
                    <div class="col-6">
                        <label class="form-label-sm">Duration (Days)</label>
                        <input type="number" id="trialDays" class="form-control" placeholder="1">
                    </div>
                </div>
            </div>

            <div class="custom-card card-body-custom">
                <h6 class="text-primary mb-3"><i class="fa-brands fa-telegram"></i> Telegram Settings</h6>
                <div class="mb-2"><label class="form-label-sm">Bot Token</label><input type="text" id="tgToken" class="form-control"></div>
                <hr>
                <div class="d-flex justify-content-between align-items-center mb-2">
                    <h6 class="text-primary m-0">👥 Admins List</h6>
                    <button class="btn btn-sm btn-primary rounded-pill" onclick="addAdmin()">+ Add</button>
                </div>
                <div id="adminList"></div>
            </div>
            
            <div class="custom-card card-body-custom">
                <h6 class="text-success mb-3"><i class="fa-solid fa-keyboard"></i> Button Texts</h6>
                <div class="section-header text-muted">Main Menu</div>
                <div class="row g-2 mb-3">
                    <div class="col-6"><label class="form-label-sm">Buy Key</label><input type="text" id="txtBuy" class="form-control form-control-sm"></div>
                    <div class="col-6"><label class="form-label-sm">Free Trial</label><input type="text" id="txtFree" class="form-control form-control-sm"></div>
                    <div class="col-6"><label class="form-label-sm">Reseller</label><input type="text" id="txtRes" class="form-control form-control-sm"></div>
                    <div class="col-6"><label class="form-label-sm">Contact</label><input type="text" id="txtCon" class="form-control form-control-sm"></div>
                </div>
                <div class="section-header text-muted">Reseller Menu</div>
                <div class="row g-2">
                    <div class="col-6"><label class="form-label-sm">Balance (Prefix)</label><input type="text" id="txtResBal" class="form-control form-control-sm" placeholder="💰 Balance"></div>
                    <div class="col-6"><label class="form-label-sm">Create Key</label><input type="text" id="txtResCreate" class="form-control form-control-sm"></div>
                    <div class="col-6"><label class="form-label-sm">Extend User</label><input type="text" id="txtResExtend" class="form-control form-control-sm"></div>
                    <div class="col-6"><label class="form-label-sm">Logout</label><input type="text" id="txtResLogout" class="form-control form-control-sm"></div>
                </div>
            </div>
        </div>

        <div class="tab-pane fade" id="tab-server">
            <div class="d-flex justify-content-between align-items-center mb-3 px-2">
                <span class="fw-bold text-secondary">Servers</span>
                <button type="button" class="btn btn-primary btn-sm rounded-pill px-3" onclick="addServer()">Add</button>
            </div>
            <div id="serverList" class="accordion"></div>
        </div>
        <div class="tab-pane fade" id="tab-plans">
            <div class="d-flex justify-content-between align-items-center mb-3 px-2">
                <span class="fw-bold text-secondary">Plans</span>
                <button type="button" class="btn btn-success btn-sm rounded-pill px-3" onclick="addPlan('plans')">Add</button>
            </div>
            <div id="planList"></div>
        </div>
        <div class="tab-pane fade" id="tab-reseller">
             <div class="d-flex justify-content-between align-items-center mb-3 px-2">
                <span class="fw-bold text-secondary">Resellers</span>
                <button type="button" class="btn btn-primary btn-sm rounded-pill px-3" onclick="addReseller()">Add User</button>
            </div>
            <div id="resellerList" class="accordion"></div>
            <hr class="my-4">
            <div class="d-flex justify-content-between align-items-center mb-3 px-2">
                <span class="fw-bold text-secondary">Reseller Plans</span>
                <button type="button" class="btn btn-warning btn-sm rounded-pill px-3 text-white" onclick="addPlan('resellerPlans')">Add Plan</button>
            </div>
            <div id="resellerPlanList" class="accordion"></div>
        </div>
    </div>
</div>

<div class="fab-container">
    <button type="button" class="btn btn-primary btn-fab" onclick="saveConfig()"><i class="fa-solid fa-floppy-disk"></i></button>
</div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<script>
    let config = { 
        telegram: { admins: [], texts: {} }, 
        trial: { enabled: false, limitGB: 1, days: 1 }, 
        protocols: { vless: true, vmess: true, ss: true },
        servers: [], plans: [], resellers: [], resellerPlans: [] 
    };

    window.onload = async () => {
        const res = await fetch('/api/config');
        if (res.ok) {
            const data = await res.json();
            // Merge loaded data with default structure
            config = { ...config, ...data };
            // Ensure nested objects exist
            if(!config.telegram.admins) config.telegram.admins = [];
            if(!config.telegram.texts) config.telegram.texts = {};
            if(!config.trial) config.trial = { enabled: false, limitGB: 1, days: 1 };
            if(!config.protocols) config.protocols = { vless: true, vmess: true, ss: true };
            
            loadFormData(); 
            renderServers(); 
            renderPlans('plans', 'planList', false); 
            renderResellers(); 
            renderPlans('resellerPlans', 'resellerPlanList', true); 
            renderAdmins();
        }
    };

    function loadFormData() {
        document.getElementById('tgToken').value = config.telegram.token || '';
        
        // Load Protocols
        document.getElementById('swVless').checked = config.protocols.vless;
        document.getElementById('swVmess').checked = config.protocols.vmess;
        document.getElementById('swSS').checked = config.protocols.ss;

        // Load Trial
        document.getElementById('swTrial').checked = config.trial.enabled;
        document.getElementById('trialGB').value = config.trial.limitGB || 1;
        document.getElementById('trialDays').value = config.trial.days || 1;

        // Texts
        const txt = config.telegram.texts;
        document.getElementById('txtBuy').value = txt.buyBtn || '🛒 Buy Key';
        document.getElementById('txtFree').value = txt.freeBtn || '🎁 Free Trial';
        document.getElementById('txtRes').value = txt.resellerBtn || '🤝 Reseller Login';
        document.getElementById('txtCon').value = txt.contactBtn || '🆘 Contact Admin';
        document.getElementById('txtResBal').value = txt.resBalance || '💰 Balance';
        document.getElementById('txtResCreate').value = txt.resCreate || '➕ Create Key';
        document.getElementById('txtResExtend').value = txt.resExtend || '👥 Extend User';
        document.getElementById('txtResLogout').value = txt.resLogout || '🚪 Logout';
    }

    function renderAdmins() {
        const list = document.getElementById('adminList');
        list.innerHTML = '';
        config.telegram.admins.forEach((admin, i) => {
            const div = document.createElement('div');
            div.className = 'input-group mb-2';
            div.innerHTML = `
                <span class="input-group-text">ID</span>
                <input type="number" class="form-control" value="${admin.id}" oninput="updateAdmin(${i}, 'id', this.value)">
                <span class="input-group-text">User</span>
                <input type="text" class="form-control" value="${admin.username}" oninput="updateAdmin(${i}, 'username', this.value)">
                <button class="btn btn-outline-danger" onclick="delAdmin(${i})">X</button>
            `;
            list.appendChild(div);
        });
    }

    window.addAdmin = () => { config.telegram.admins.push({ id: 0, username: "admin" }); renderAdmins(); };
    window.delAdmin = (i) => { config.telegram.admins.splice(i, 1); renderAdmins(); };
    window.updateAdmin = (i, key, val) => { config.telegram.admins[i][key] = key === 'id' ? parseInt(val) : val; };

    // Standard Render Functions
    function renderServers(){const e=document.getElementById("serverList");e.innerHTML="",config.servers.forEach(((t,n)=>{const a=document.createElement("div");a.className="custom-card",a.innerHTML=`<div class="server-header d-flex justify-content-between" data-bs-toggle="collapse" data-bs-target="#col${n}"><span><span class="badge bg-primary rounded-circle">#${n+1}</span> <b>${t.name}</b></span><button class="btn btn-sm text-danger" onclick="delSrv(${n})"><i class="fa-solid fa-trash"></i></button></div><div id="col${n}" class="collapse"><div class="card-body-custom border-top"><div class="mb-2"><label class="form-label-sm">Name</label><input type="text" class="form-control" value="${t.name}" oninput="updateData('servers', ${n}, 'name', this.value)"></div><div class="mb-2"><label class="form-label-sm">URL</label><input type="text" class="form-control" value="${t.url}" oninput="updateData('servers', ${n}, 'url', this.value)"></div><div class="row g-2 mb-2"><div class="col-6"><input type="text" class="form-control" value="${t.username}" placeholder="User" oninput="updateData('servers', ${n}, 'username', this.value)"></div><div class="col-6"><input type="password" class="form-control" value="${t.password}" placeholder="Pass" oninput="updateData('servers', ${n}, 'password', this.value)"></div></div><div class="section-header text-primary">Inbound IDs</div><div class="row g-2"><div class="col-4"><label class="form-label-sm">VLESS ID</label><input type="number" class="form-control" value="${t.vlessId}" oninput="updateData('servers', ${n}, 'vlessId', this.value)"></div><div class="col-4"><label class="form-label-sm">VMESS ID</label><input type="number" class="form-control" value="${t.vmessId}" oninput="updateData('servers', ${n}, 'vmessId', this.value)"></div><div class="col-4"><label class="form-label-sm">SS ID</label><input type="number" class="form-control" value="${t.ssId}" oninput="updateData('servers', ${n}, 'ssId', this.value)"></div></div></div></div>`,e.appendChild(a)}))}
    function renderResellers(){const e=document.getElementById("resellerList");e.innerHTML="",config.resellers.forEach(((t,n)=>{const a=document.createElement("div");a.className="custom-card",a.innerHTML=`<div class="server-header d-flex justify-content-between" data-bs-toggle="collapse" data-bs-target="#resCol${n}"><span><span class="badge bg-info rounded-circle">#${n+1}</span> <b>${t.username}</b></span><button class="btn btn-sm text-danger" onclick="delReseller(${n})"><i class="fa-solid fa-trash"></i></button></div><div id="resCol${n}" class="collapse"><div class="card-body-custom border-top"><div class="row g-2"><div class="col-12"><label class="form-label-sm">Username</label><input type="text" class="form-control" value="${t.username}" oninput="updateData('resellers', ${n}, 'username', this.value)"></div><div class="col-6"><label class="form-label-sm">Password</label><input type="text" class="form-control" value="${t.password}" oninput="updateData('resellers', ${n}, 'password', this.value)"></div><div class="col-6"><label class="form-label-sm">Balance</label><input type="number" class="form-control border-success" value="${t.balance}" oninput="updateData('resellers', ${n}, 'balance', this.value)"></div></div></div></div>`,e.appendChild(a)}))}
    function renderPlans(e,t,n){const a=document.getElementById(t);a.innerHTML="",config[e].forEach(((t,s)=>{const l=document.createElement("div");n?(l.className="custom-card",l.innerHTML=`<div class="server-header d-flex justify-content-between" data-bs-toggle="collapse" data-bs-target="#plan${e}${s}"><span><span class="badge bg-warning rounded-circle">#${s+1}</span> <b>${t.name}</b></span><button class="btn btn-sm text-danger" onclick="delPlan('${e}', ${s})"><i class="fa-solid fa-trash"></i></button></div><div id="plan${e}${s}" class="collapse"><div class="card-body-custom border-top"><div class="mb-2"><label class="form-label-sm">Plan Name</label><input class="form-control" value="${t.name}" oninput="updateData('${e}', ${s}, 'name', this.value)"></div><div class="row g-2"><div class="col-4"><label class="form-label-sm">Price</label><input type="number" class="form-control" value="${t.price}" oninput="updateData('${e}', ${s}, 'price', this.value)"></div><div class="col-4"><label class="form-label-sm">Limit GB</label><input type="number" class="form-control" value="${t.limitGB}" oninput="updateData('${e}', ${s}, 'limitGB', this.value)"></div><div class="col-4"><label class="form-label-sm">Days</label><input type="number" class="form-control" value="${t.days}" oninput="updateData('${e}', ${s}, 'days', this.value)"></div></div></div></div>`):(l.className="custom-card card-body-custom py-2",l.innerHTML=`<div class="row g-2 align-items-center"><div class="col-12 d-flex justify-content-between"><input class="form-control form-control-sm border-0 fw-bold" value="${t.name}" placeholder="Name" oninput="updateData('${e}', ${s}, 'name', this.value)"><button class="btn btn-sm text-danger" onclick="delPlan('${e}', ${s})"><i class="fa-solid fa-times"></i></button></div><div class="col-4"><input type="number" class="form-control form-control-sm" value="${t.price}" placeholder="Price" oninput="updateData('${e}', ${s}, 'price', this.value)"></div><div class="col-4"><input type="number" class="form-control form-control-sm" value="${t.limitGB}" placeholder="GB" oninput="updateData('${e}', ${s}, 'limitGB', this.value)"></div><div class="col-4"><input type="number" class="form-control form-control-sm" value="${t.days}" placeholder="Days" oninput="updateData('${e}', ${s}, 'days', this.value)"></div></div>`),a.appendChild(l)}))}

    window.addServer = () => { config.servers.push({ name: "New", url: "http://127.0.0.1:2053", username: "admin", password: "password", vlessId: 0, vmessId: 0, ssId: 0 }); renderServers(); };
    window.delSrv = (i) => { if(confirm("Del?")) { config.servers.splice(i, 1); renderServers(); } };
    window.addPlan = (t) => { config[t].push({ name: "Plan", price: 1000, limitGB: 10, days: 30 }); if(t==='plans') renderPlans('plans','planList',false); else renderPlans('resellerPlans','resellerPlanList',true); };
    window.delPlan = (t, i) => { if(confirm("Del?")) { config[t].splice(i, 1); if(t==='plans') renderPlans('plans','planList',false); else renderPlans('resellerPlans','resellerPlanList',true); } };
    window.addReseller = () => { config.resellers.push({ username: "user", password: "123", balance: 0 }); renderResellers(); };
    window.delReseller = (i) => { if(confirm("Del?")) { config.resellers.splice(i, 1); renderResellers(); } };
    window.updateData = (arr, idx, key, val) => { if(['vlessId','vmessId','ssId','price','limitGB','days','adminId','balance'].includes(key)) val = parseInt(val)||0; config[arr][idx][key] = val; };

    window.saveConfig = async () => {
        config.telegram.token = document.getElementById('tgToken').value;
        
        // Save Protocols (New)
        config.protocols = {
            vless: document.getElementById('swVless').checked,
            vmess: document.getElementById('swVmess').checked,
            ss: document.getElementById('swSS').checked
        };

        // Save Trial (New)
        config.trial = {
            enabled: document.getElementById('swTrial').checked,
            limitGB: parseFloat(document.getElementById('trialGB').value) || 1,
            days: parseInt(document.getElementById('trialDays').value) || 1
        };

        // Save Texts
        config.telegram.texts = {
            buyBtn: document.getElementById('txtBuy').value,
            freeBtn: document.getElementById('txtFree').value,
            resellerBtn: document.getElementById('txtRes').value,
            contactBtn: document.getElementById('txtCon').value,
            adminBtn: "👮 Admin Panel",
            resBalance: document.getElementById('txtResBal').value,
            resCreate: document.getElementById('txtResCreate').value,
            resExtend: document.getElementById('txtResExtend').value,
            resLogout: document.getElementById('txtResLogout').value
        };

        await fetch('/api/config', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(config) });
        alert("Saved Settings & Protocols!"); setTimeout(() => location.reload(), 1000);
    };
</script>
</body>
</html>
EOF

echo -e "${GREEN}Success! index.html saved to $DIR/index.html${NC}"
