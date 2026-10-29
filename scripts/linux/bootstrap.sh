#!/bin/bash
set -e

# ==========================================
# GESTION DE L'ARGUMENT UTILISATEUR
# ==========================================
# Usage : ./bootstrap.sh <username> OU ./bootstrap.sh -u <username>
TARGET_USER="$1"

if [ "$1" = "-u" ] || [ "$1" = "--username" ]; then
    TARGET_USER="$2"
fi

if [ -z "$TARGET_USER" ]; then
    echo "Erreur : nom d'utilisateur manquant."
    echo "Usage : $0 <nom_utilisateur>"
    echo "Exemple : $0 mickael"
    exit 1
fi

echo "==> Initialisation de l'environnement pour l'utilisateur : $TARGET_USER"

# ==========================================
# 1. CRÉATION DE L'UTILISATEUR & SUDO
# ==========================================
if id "$TARGET_USER" &>/dev/null; then
    echo "==> L'utilisateur '$TARGET_USER' existe déjà."
else
    echo "==> Création de l'utilisateur '$TARGET_USER'..."
    useradd -m -s /bin/bash "$TARGET_USER"
    echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$TARGET_USER"
    chmod 0440 "/etc/sudoers.d/$TARGET_USER"
fi

# ==========================================
# 2. DÉPENDANCES ET DÉPÔT DOCKER
# ==========================================
echo "==> Configuration du dépôt Docker officiel..."
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

# ==========================================
# 3. INSTALLATION DOCKER CE & GROUPES
# ==========================================
echo "==> Installation de Docker CE..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

usermod -aG docker "$TARGET_USER"

# ==========================================
# 4. CONFIGURATION WSL (/etc/wsl.conf)
# ==========================================
echo "==> Mise à jour de /etc/wsl.conf..."
cat <<EOF > /etc/wsl.conf
[boot]
systemd=true

[user]
default=$TARGET_USER
EOF

echo ""
echo "Terminé avec succès pour '$TARGET_USER'."
echo "Depuis PowerShell sous Windows, exécute : wsl --shutdown"