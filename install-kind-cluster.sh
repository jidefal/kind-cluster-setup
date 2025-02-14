#!/usr/bin/env bash

set -eo pipefail

# Configuration
CLUSTER_NAME=${1:-kind}
KIND_VERSION="v0.22.0"  # Specify your desired KIND version

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root. Please use sudo.${NC}"
    exit 1
fi

# Function to handle errors
handle_error() {
    local line=$1
    echo -e "${RED}An error occurred on line $line${NC}"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Detect OS and package manager
detect_os() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        case $ID in
            ubuntu|debian)
                PM="apt"
                ;;
            centos|rhel|fedora)
                PM="yum"
                ;;
            *)
                echo -e "${RED}Unsupported operating system: $ID${NC}"
                exit 1
                ;;
        esac
    else
        echo -e "${RED}Unsupported operating system${NC}"
        exit 1
    fi
}

# Install Docker
install_docker() {
    echo -e "${YELLOW}Installing Docker...${NC}"
    case $PM in
        apt)
            apt update
            apt install -y apt-transport-https ca-certificates curl software-properties-common
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt update
            apt install -y docker-ce docker-ce-cli containerd.io
            ;;
        yum)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
            ;;
    esac

    systemctl enable --now docker
    echo -e "${GREEN}Docker installed successfully!${NC}"
}

# Install kubectl
install_kubectl() {
    echo -e "${YELLOW}Installing kubectl...${NC}"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    echo -e "${GREEN}kubectl installed successfully!${NC}"
}

# Install KIND
install_kind() {
    echo -e "${YELLOW}Installing KIND...${NC}"
    curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
    chmod +x ./kind
    mv ./kind /usr/local/bin/kind
    echo -e "${GREEN}KIND installed successfully!${NC}"
}

# Setup user permissions
setup_permissions() {
    if [ -n "$SUDO_USER" ]; then
        echo -e "${YELLOW}Setting up user permissions...${NC}"
        usermod -aG docker "$SUDO_USER"
        mkdir -p "/home/$SUDO_USER/.kube"
        chown "$SUDO_USER:" "/home/$SUDO_USER/.kube"
    fi
}

# Create KIND cluster
create_cluster() {
    echo -e "${YELLOW}Creating KIND cluster '$CLUSTER_NAME'...${NC}"
    su - "$SUDO_USER" -c "kind create cluster --name $CLUSTER_NAME"
    echo -e "${GREEN}KIND cluster created successfully!${NC}"

    # Copy kubeconfig to user directory
    if [ -n "$SUDO_USER" ]; then
        local user_home=$(eval echo ~$SUDO_USER)
        cp /root/.kube/config "$user_home/.kube/config"
        chown "$SUDO_USER:" "$user_home/.kube/config"
        echo -e "${YELLOW}Kubeconfig copied to user directory${NC}"
    fi
}

# Verify installations
verify_installations() {
    echo -e "\n${YELLOW}Verifying installations:${NC}"
    docker --version
    kubectl version --client
    kind --version
}

# Main function
main() {
    detect_os
    install_docker
    install_kubectl
    install_kind
    setup_permissions
    create_cluster
    verify_installations
    
    echo -e "\n${GREEN}Setup completed successfully!${NC}"
    echo -e "You can now use the cluster with:"
    echo -e "  kubectl cluster-info"
    
    if [ -n "$SUDO_USER" ]; then
        echo -e "\n${YELLOW}Note: You might need to log out and back in for group changes to take effect!${NC}"
    fi
}

# Execute main function
main