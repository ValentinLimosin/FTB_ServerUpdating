#!/bin/bash
# Script de mise à jour du serveur Minecraft FTB Evolution
# utilisant l'installeur binaire de FTB en mode automatique,
# avec sauvegarde/restauration des données importantes.
# Prérequis : curl, jq et wget doivent être installés sur votre système

# Configuration initiale
PACK_ID=XXX #Mettre l'id du Mod pack

# Répertoire de base où sont stockées les versions (ex: /servers/minecraft/1.10, /servers/minecraft/1.21, etc.)
BASE_DIR="$HOME/servers/minecraft"

# Détection automatique de la version actuelle en lisant les noms de dossiers dans BASE_DIR
if ls -1 "$BASE_DIR" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' >/dev/null; then
    VERSION_ACTUELLE=$(ls -1 "$BASE_DIR" | grep -E '^[0-9]+\.[0-9]+' | sort -V | tail -n 1)
else
    echo "Aucune version détectée dans $BASE_DIR, utilisation de la valeur par défaut 1.0."
    VERSION_ACTUELLE="1.0"
fi

echo "Version actuelle détectée : $VERSION_ACTUELLE"

# Définition des chemins pour les instances actuelles
SERVERS_DIR="$HOME/servers/minecraft/$VERSION_ACTUELLE"
CREA_DIR="$SERVERS_DIR/Crea"
SURV_DIR="$SERVERS_DIR/Surv"
# Nom du dossier world pour le serveur Survival
SURV_WORLD="world" #A changer si le monde a un nom particulier

# Dossiers de backup et dossier temporaire
BACKUP_DIR="$HOME/servers/minecraft/backup_$(date +%Y%m%d_%H%M%S)"
TEMP_DIR="$HOME/tmp/ftb_evolution_update"

echo "Création du dossier de backup : $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# Fonction de sauvegarde des fichiers d'une instance
backup_instance() {
    local instance_dir="$1"
    local instance_label="$2"
    
    echo "Sauvegarde de l'instance $instance_label dans $instance_dir..."
    # Sauvegarde du dossier world ou du dossier de monde personnalisé pour Survival
    if [ "$instance_label" == "surv" ]; then
        cp -r "$instance_dir/$SURV_WORLD" "$BACKUP_DIR/world_$instance_label"
    else
        cp -r "$instance_dir/world" "$BACKUP_DIR/world_$instance_label"
    fi
    
    # Sauvegarde des fichiers importants s'ils existent
    for file in server.properties ops.json banned-players.json banned-ips.json whitelist.json; do
        if [ -f "$instance_dir/$file" ]; then
            cp "$instance_dir/$file" "$BACKUP_DIR/${file%.*}_$instance_label.${file##*.}"
        fi
    done
}

# Sauvegarde des deux instances
backup_instance "$CREA_DIR" "crea"
backup_instance "$SURV_DIR" "surv"

# Arrêt des serveurs (à adapter selon l'environnement)
echo "Arrêt des serveurs..."
screen -S crea -X stuff "stop$(printf \\r)"
screen -S surv -X stuff "stop$(printf \\r)"
Sleep 10

# Récupération des informations du modpack via l'API fee-the-beast
API_URL="https://api.feed-the-beast.com/v1/modpacks/public/modpack/${PACK_ID}"
echo "Récupération des informations du pack depuis $API_URL..."
PACK_INFO=$(curl -s "$API_URL")
if [ -z "$PACK_INFO" ]; then
    echo "Erreur lors de la récupération des informations du pack."
    exit 1
fi

# Extraction de la dernière version (dernier élément du tableau "versions")
VERSION_ID=$(echo "$PACK_INFO" | jq '.versions | last | .id')
NEW_VERSION=$(echo "$PACK_INFO" | jq -r '.versions | last | .name')

if [ "$VERSION_ID" = "null" ] || [ -z "$VERSION_ID" ]; then
    echo "ID de version introuvable dans la réponse API."
    exit 1
fi

if [ "$NEW_VERSION" = "null" ] || [ -z "$NEW_VERSION" ]; then
    echo "Numéro de version introuvable dans la réponse API."
    exit 1
fi

echo "Dernière version détectée : $NEW_VERSION (ID : $VERSION_ID)"

# Définition des nouveaux dossiers d'installation basés sur la nouvelle version
NOUVELLE_DIR="$HOME/servers/minecraft/$NEW_VERSION"
NEW_CREA_DIR="$NOUVELLE_DIR/Crea"
NEW_SURV_DIR="$NOUVELLE_DIR/Surv"

echo "Création des dossiers pour la nouvelle version..."
mkdir -p "$NEW_CREA_DIR" "$NEW_SURV_DIR"

# Téléchargement de l’installeur binaire
# Cet endpoint retourne un exécutable Linux
INSTALLER_URL="https://api.feed-the-beast.com/v1/modpacks/public/modpack/${PACK_ID}/${VERSION_ID}/server/linux"
echo "Téléchargement de l’installeur binaire depuis $INSTALLER_URL..."
mkdir -p "$TEMP_DIR"
INSTALLER_BINARY="$TEMP_DIR/ftb_installer"
wget -O "$INSTALLER_BINARY" "$INSTALLER_URL"
if [ $? -ne 0 ]; then
    echo "Erreur lors du téléchargement de l’installeur."
    exit 1
fi
chmod +x "$INSTALLER_BINARY"

# Exécution de l’installeur pour l'instance Créatif
echo "Installation du modpack dans $NEW_CREA_DIR..."
"$INSTALLER_BINARY" -pack "$PACK_ID" -version "$VERSION_ID" -dir "$NEW_CREA_DIR" -auto -force
if [ $? -ne 0 ]; then
    echo "Erreur lors de l'installation pour l'instance Créatif."
    exit 1
fi

# Exécution de l’installeur pour l'instance Survie
echo "Installation du modpack dans $NEW_SURV_DIR..."
"$INSTALLER_BINARY" -pack "$PACK_ID" -version "$VERSION_ID" -dir "$NEW_SURV_DIR" -auto -force
if [ $? -ne 0 ]; then
    echo "Erreur lors de l'installation pour l'instance Survie."
    exit 1
fi

# Fonction de restauration des fichiers d'une instance
restore_instance() {
    local new_dir="$1"
    local instance_label="$2"
    
    echo "Restauration de l'instance $instance_label dans $new_dir..."
    # Pour l'instance Survival, on restaure dans le dossier Ethernal_Horizons
    if [ "$instance_label" == "surv" ]; then
        rm -rf "$new_dir/world"
        cp -r "$BACKUP_DIR/world_$instance_label" "$new_dir/$SURV_WORLD"
    else
        rm -rf "$new_dir/world"
        cp -r "$BACKUP_DIR/world_$instance_label" "$new_dir/world"
    fi
    
    # Restauration des fichiers importants si sauvegardés
    for file in server.properties ops.json banned-players.json banned-ips.json whitelist.json; do
        backup_file="$BACKUP_DIR/${file%.*}_$instance_label.${file##*.}"
        if [ -f "$backup_file" ]; then
            cp "$backup_file" "$new_dir/$file"
        fi
    done
}

# Restauration des instances
restore_instance "$NEW_CREA_DIR" "crea"
restore_instance "$NEW_SURV_DIR" "surv"

# Nettoyage du dossier temporaire
echo "Nettoyage du dossier temporaire..."
rm -rf "$TEMP_DIR"
# Nettoyage de l'ancienne instance, a commenter si vous souhaitez garder
echo "Nettoyage de l'instance précédente..."
rm -rf "$SERVERS_DIR"

#Kill all screens and recreate to launch the new minecraft
echo "Re-démarage server..."
killall screen
#Survie
screen -S surv -X stuff "$NEW_SURV_DIR/run.sh$(printf \\r)"
#Creatif
screen -S crea -X stuff "$NEW_CREA_DIR/run.sh$(printf \\r)"

echo "Mise à jour terminée avec succès."
echo "Server en cours de démarage... aller accepter l'EULA"