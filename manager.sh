#!/bin/bash

# RSA Manager - Gestion des clés RSA et configuration SSH
# Auteur: Script de gestion automatisé
# Date: Septembre 2025

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Répertoires
SSH_DIR="$HOME/.ssh"
CONFIG_FILE="$SSH_DIR/config"

# Fonction d'affichage avec couleurs
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Vérifier si le répertoire SSH existe
check_ssh_directory() {
    if [ ! -d "$SSH_DIR" ]; then
        print_info "Création du répertoire SSH..."
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        print_success "Répertoire SSH créé : $SSH_DIR"
    fi
}

# Créer le fichier config s'il n'existe pas
check_config_file() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_info "Création du fichier config SSH..."
        touch "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
        print_success "Fichier config créé : $CONFIG_FILE"
    fi
}

# Fonction pour créer une paire de clés RSA
create_rsa_key() {
    echo
    print_info "=== CRÉATION D'UNE NOUVELLE PAIRE DE CLÉS RSA ==="
    
    # Demander les informations
    read -p "Nom du serveur (ID) : " server_id
    read -p "Hostname/IP du serveur : " hostname
    read -p "Nom d'utilisateur : " username
    read -p "Taille de la clé RSA [4096] : " key_size
    
    # Valeur par défaut pour la taille de clé
    if [[ -z "$key_size" ]]; then
        key_size=4096
    fi
    
    # Validation des entrées
    if [[ -z "$server_id" || -z "$hostname" || -z "$username" ]]; then
        print_error "Tous les champs sont obligatoires !"
        return 1
    fi
    
    # Validation de la taille de clé
    if ! [[ "$key_size" =~ ^[0-9]+$ ]] || [ "$key_size" -lt 1024 ]; then
        print_error "La taille de clé doit être un nombre entier >= 1024 !"
        return 1
    fi
    
    # Nom de la clé
    key_name="${server_id}.key"
    key_path="$SSH_DIR/$key_name"
    
    # Vérifier si la clé existe déjà
    if [ -f "$key_path" ]; then
        print_warning "La clé $key_name existe déjà !"
        read -p "Voulez-vous la remplacer ? (y/N) : " replace
        if [[ ! "$replace" =~ ^[Yy]$ ]]; then
            print_info "Opération annulée."
            return 0
        fi
        rm -f "$key_path" "$key_path.pub"
    fi
    
    # Générer la paire de clés RSA
    print_info "Génération de la paire de clés RSA (${key_size} bits)..."
    ssh-keygen -t rsa -b "$key_size" -f "$key_path" -N "" -C "${username}@${hostname}"
    
    if [ $? -eq 0 ]; then
        print_success "Paire de clés générée : $key_path"
        chmod 600 "$key_path"
        chmod 644 "$key_path.pub"
    else
        print_error "Erreur lors de la génération des clés"
        return 1
    fi
    
    # Ajouter/Mettre à jour la configuration SSH
    update_ssh_config "$server_id" "$hostname" "$username" "$key_path"
    
    # Afficher la clé publique
    echo
    print_info "Clé publique générée :"
    echo "$(cat "$key_path.pub")"
    echo
    print_info "Vous pouvez maintenant copier cette clé sur le serveur avec :"
    print_info "ssh-copy-id -i $key_path.pub $username@$hostname"
    echo
    print_success "Configuration terminée ! Vous pouvez vous connecter avec : ssh $server_id"
}

# Fonction pour mettre à jour le fichier config SSH
update_ssh_config() {
    local server_id="$1"
    local hostname="$2"
    local username="$3"
    local key_path="$4"
    
    # Supprimer l'ancienne configuration si elle existe
    remove_ssh_config_entry "$server_id"
    
    # Ajouter la nouvelle configuration
    print_info "Ajout de la configuration SSH..."
    
    cat >> "$CONFIG_FILE" << EOF

Host $server_id
    Hostname $hostname
    User $username
    IdentityFile $key_path
EOF
    
    print_success "Configuration SSH ajoutée pour $server_id"
}

# Fonction pour supprimer une entrée du config SSH
remove_ssh_config_entry() {
    local server_id="$1"
    
    if grep -q "^Host $server_id$" "$CONFIG_FILE" 2>/dev/null; then
        print_info "Suppression de l'ancienne configuration pour $server_id..."
        
        # Créer un fichier temporaire sans l'entrée à supprimer
        awk -v host="$server_id" '
        BEGIN { skip = 0 }
        /^Host / { 
            if ($2 == host) { 
                skip = 1 
            } else { 
                skip = 0 
            } 
        }
        /^$/ { skip = 0 }
        !skip { print }
        ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
        
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
}

# Fonction pour supprimer une paire de clés
delete_rsa_key() {
    echo
    print_info "=== SUPPRESSION D'UNE PAIRE DE CLÉS RSA ==="
    
    # Lister les clés disponibles
    echo "Clés disponibles :"
    ls -1 "$SSH_DIR"/*.key 2>/dev/null | while read key_file; do
        if [ -f "$key_file" ]; then
            basename "$key_file" .key
        fi
    done
    echo
    
    read -p "Nom du serveur à supprimer : " server_id
    
    if [[ -z "$server_id" ]]; then
        print_error "Le nom du serveur est obligatoire !"
        return 1
    fi
    
    key_name="${server_id}.key"
    key_path="$SSH_DIR/$key_name"
    
    # Vérifier si la clé existe
    if [ ! -f "$key_path" ]; then
        print_error "La clé $key_name n'existe pas !"
        return 1
    fi
    
    # Confirmation
    print_warning "Vous êtes sur le point de supprimer :"
    echo "  - Clé privée : $key_path"
    echo "  - Clé publique : $key_path.pub"
    echo "  - Configuration SSH pour $server_id"
    echo
    read -p "Êtes-vous sûr ? (y/N) : " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Supprimer les fichiers de clés
        rm -f "$key_path" "$key_path.pub"
        
        # Supprimer la configuration SSH
        remove_ssh_config_entry "$server_id"
        
        print_success "Paire de clés et configuration supprimées pour $server_id"
    else
        print_info "Suppression annulée."
    fi
}

# Fonction pour lister les clés existantes
list_keys() {
    echo
    print_info "=== CLÉS RSA DISPONIBLES ==="
    
    if ! ls "$SSH_DIR"/*.key >/dev/null 2>&1; then
        print_warning "Aucune clé RSA trouvée dans $SSH_DIR"
        return 0
    fi
    
    echo "┌─────────────────┬──────────────────────────────────────┬─────────────────┐"
    echo "│ Serveur         │ Chemin de la clé                     │ Configuration   │"
    echo "├─────────────────┼──────────────────────────────────────┼─────────────────┤"
    
    for key_file in "$SSH_DIR"/*.key; do
        if [ -f "$key_file" ]; then
            server_name=$(basename "$key_file" .key)
            config_exists="Non"
            
            if grep -q "^Host $server_name$" "$CONFIG_FILE" 2>/dev/null; then
                config_exists="Oui"
            fi
            
            printf "│ %-15s │ %-36s │ %-15s │\n" "$server_name" "$key_file" "$config_exists"
        fi
    done
    
    echo "└─────────────────┴──────────────────────────────────────┴─────────────────┘"
}

# Fonction pour afficher l'aide
show_help() {
    echo
    echo "RSA Manager - Gestionnaire de clés RSA et configuration SSH"
    echo
    echo "USAGE:"
    echo "  $0 [OPTION]"
    echo
    echo "OPTIONS:"
    echo "  create, c    Créer une nouvelle paire de clés RSA"
    echo "  delete, d    Supprimer une paire de clés RSA"
    echo "  list, l      Lister les clés existantes"
    echo "  help, h      Afficher cette aide"
    echo
    echo "EXEMPLES:"
    echo "  $0 create    # Mode interactif pour créer une clé"
    echo "  $0 delete    # Mode interactif pour supprimer une clé"
    echo "  $0 list      # Afficher toutes les clés"
    echo
}

# Menu principal
show_menu() {
    echo
    echo "========================================="
    echo "    RSA Manager - Menu Principal"
    echo "========================================="
    echo "1. Créer une nouvelle paire de clés RSA"
    echo "2. Supprimer une paire de clés RSA"
    echo "3. Lister les clés existantes"
    echo "4. Aide"
    echo "5. Quitter"
    echo "========================================="
    read -p "Choisissez une option (1-5) : " choice
    
    case $choice in
        1) create_rsa_key ;;
        2) delete_rsa_key ;;
        3) list_keys ;;
        4) show_help ;;
        5) print_info "Au revoir !"; exit 0 ;;
        *) print_error "Option invalide !" ;;
    esac
}

# Fonction principale
main() {
    # Vérifications initiales
    check_ssh_directory
    check_config_file
    
    # Gestion des arguments en ligne de commande
    case "${1:-}" in
        "create"|"c")
            create_rsa_key
            ;;
        "delete"|"d")
            delete_rsa_key
            ;;
        "list"|"l")
            list_keys
            ;;
        "help"|"h"|"--help")
            show_help
            ;;
        "")
            # Mode interactif
            while true; do
                show_menu
                echo
                read -p "Appuyez sur Entrée pour continuer..."
            done
            ;;
        *)
            print_error "Option inconnue : $1"
            show_help
            exit 1
            ;;
    esac
}

# Point d'entrée du script
main "$@"