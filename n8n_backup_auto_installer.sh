#!/bin/bash

#############################################
# N8N BACKUP AUTO INSTALLER
# Tự động cài đặt và cấu hình backup service
#############################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}N8N BACKUP SERVICE - AUTO INSTALLER${NC}                   ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_step() {
    echo -e "${BLUE}➤${NC} ${BOLD}$1${NC}"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log_error "Script này cần chạy với quyền root (sudo)"
        exit 1
    fi
    log_success "Đang chạy với quyền root"
}

# Check if Docker is installed
check_docker() {
    log_step "Kiểm tra Docker..."
    if ! command -v docker &> /dev/null; then
        log_error "Docker chưa được cài đặt!"
        exit 1
    fi
    log_success "Docker đã được cài đặt"
}

# Check if n8n container exists
check_n8n_container() {
    log_step "Tìm kiếm n8n container..."
    CONTAINER=$(docker ps --filter "name=n8n" --format "{{.Names}}" | head -n 1)
    
    if [ -z "$CONTAINER" ]; then
        log_error "Không tìm thấy n8n container đang chạy!"
        echo ""
        echo "Danh sách containers đang chạy:"
        docker ps --format "table {{.Names}}\t{{.Status}}"
        exit 1
    fi
    log_success "Tìm thấy n8n container: $CONTAINER"
}

# Create main backup script
create_backup_script() {
    log_step "Tạo script backup chính..."
    
    cat > /usr/local/bin/n8n-backup.sh << 'EOF'
#!/bin/bash

#############################################
# N8N AUTO BACKUP SCRIPT
# Tự động backup n8n theo 2 phương pháp
#############################################

set -euo pipefail

# ============================================
# CONFIGURATION - CÓ THỂ ĐIỀU CHỈNH
# ============================================
BACKUP_BASE_DIR="/home/minhnc/Desktop/n8n-backup"
BACKUP_INTERVAL_MINUTES=60  # Backup mỗi bao nhiêu phút (60 = mỗi giờ)
RETENTION_DAYS=30           # Giữ backup trong bao nhiêu ngày
LOG_FILE="$BACKUP_BASE_DIR/backup.log"

# ============================================
# COLORS FOR TERMINAL UI
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ============================================
# FUNCTIONS
# ============================================

print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}N8N AUTOMATIC BACKUP SYSTEM${NC}                           ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    # Log to file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Print to terminal with colors
    case $level in
        "INFO")
            echo -e "${BLUE}ℹ${NC}  [$timestamp] $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}✓${NC}  [$timestamp] ${GREEN}$message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠${NC}  [$timestamp] ${YELLOW}$message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}✗${NC}  [$timestamp] ${RED}$message${NC}"
            ;;
        "STEP")
            echo -e "${PURPLE}➤${NC}  [$timestamp] ${BOLD}$message${NC}"
            ;;
    esac
}

print_separator() {
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
}

show_config() {
    echo -e "${BOLD}📋 Configuration:${NC}"
    echo -e "   Backup Directory: ${CYAN}$BACKUP_BASE_DIR${NC}"
    echo -e "   Backup Interval:  ${CYAN}$BACKUP_INTERVAL_MINUTES minutes${NC}"
    echo -e "   Retention:        ${CYAN}$RETENTION_DAYS days${NC}"
    echo ""
    print_separator
    echo ""
}

find_n8n_container() {
    log "INFO" "Tìm kiếm n8n container..."
    CONTAINER=$(docker ps --filter "name=n8n" --format "{{.Names}}" | head -n 1)
    
    if [ -z "$CONTAINER" ]; then
        log "ERROR" "Không tìm thấy n8n container đang chạy!"
        log "INFO" "Danh sách containers đang chạy:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
        exit 1
    fi
    
    log "SUCCESS" "Tìm thấy container: $CONTAINER"
    return 0
}

backup_method_1_cli_export() {
    local backup_dir=$1
    local method_dir="$backup_dir/method1-cli-export"
    
    mkdir -p "$method_dir"
    
    log "STEP" "Phương pháp 1: Export qua N8N CLI"
    
    # Export workflows
    log "INFO" "Đang export workflows..."
    if docker exec "$CONTAINER" n8n export:workflow --all --output=/tmp/workflows.json 2>/dev/null; then
        docker cp "$CONTAINER":/tmp/workflows.json "$method_dir/workflows.json"
        docker exec "$CONTAINER" rm /tmp/workflows.json
        
        local workflow_count=$(jq '. | length' "$method_dir/workflows.json" 2>/dev/null || echo "?")
        log "SUCCESS" "Export thành công $workflow_count workflows"
    else
        log "WARNING" "Không thể export workflows (có thể chưa có workflow nào)"
    fi
    
    # Export credentials
    log "INFO" "Đang export credentials..."
    if docker exec "$CONTAINER" n8n export:credentials --all --output=/tmp/credentials.json 2>/dev/null; then
        docker cp "$CONTAINER":/tmp/credentials.json "$method_dir/credentials.json"
        docker exec "$CONTAINER" rm /tmp/credentials.json
        
        local cred_count=$(jq '. | length' "$method_dir/credentials.json" 2>/dev/null || echo "?")
        log "SUCCESS" "Export thành công $cred_count credentials"
    else
        log "WARNING" "Không thể export credentials (có thể chưa có credential nào)"
    fi
    
    # Backup encryption key
    log "INFO" "Đang backup encryption key..."
    docker inspect "$CONTAINER" --format='{{json .Config.Env}}' > "$method_dir/environment.json"
    docker inspect "$CONTAINER" | grep -i "N8N_ENCRYPTION_KEY" > "$method_dir/encryption_key.txt" 2>/dev/null || echo "N8N_ENCRYPTION_KEY not found" > "$method_dir/encryption_key.txt"
    log "SUCCESS" "Backup encryption key hoàn tất"
    
    # Create info file
    cat > "$method_dir/README.txt" << EOFL
N8N BACKUP - CLI Export Method
Generated: $(date)
Container: $CONTAINER

Files:
- workflows.json: All workflow definitions
- credentials.json: All credentials (encrypted)
- encryption_key.txt: Encryption key (IMPORTANT!)
- environment.json: Full environment variables

To restore:
1. Import workflows: n8n import:workflow --input=workflows.json
2. Import credentials: n8n import:credentials --input=credentials.json
3. Make sure to set the same N8N_ENCRYPTION_KEY
EOFL
    
    log "SUCCESS" "Phương pháp 1 hoàn tất ✓"
}

backup_method_2_database() {
    local backup_dir=$1
    local method_dir="$backup_dir/method2-full-database"
    
    mkdir -p "$method_dir"
    
    log "STEP" "Phương pháp 2: Backup Full Database"
    
    # Backup database safely using sqlite3
    log "INFO" "Đang backup database SQLite..."
    if docker exec "$CONTAINER" sqlite3 /home/node/.n8n/database.sqlite ".backup '/tmp/backup.db'" 2>/dev/null; then
        docker cp "$CONTAINER":/tmp/backup.db "$method_dir/database.sqlite"
        docker exec "$CONTAINER" rm /tmp/backup.db
        
        local db_size=$(du -h "$method_dir/database.sqlite" | cut -f1)
        log "SUCCESS" "Backup database hoàn tất (Size: $db_size)"
    else
        log "ERROR" "Không thể backup database!"
        return 1
    fi
    
    # Backup entire .n8n directory
    log "INFO" "Đang backup toàn bộ .n8n directory..."
    docker exec "$CONTAINER" tar czf /tmp/n8n-full.tar.gz /home/node/.n8n 2>/dev/null || true
    if docker cp "$CONTAINER":/tmp/n8n-full.tar.gz "$method_dir/n8n-full-backup.tar.gz" 2>/dev/null; then
        docker exec "$CONTAINER" rm /tmp/n8n-full.tar.gz
        log "SUCCESS" "Backup full directory hoàn tất"
    else
        log "WARNING" "Không thể backup full directory"
    fi
    
    # Backup encryption key
    log "INFO" "Đang backup encryption key..."
    docker inspect "$CONTAINER" --format='{{json .Config.Env}}' > "$method_dir/environment.json"
    docker inspect "$CONTAINER" | grep -i "N8N_ENCRYPTION_KEY" > "$method_dir/encryption_key.txt" 2>/dev/null || echo "N8N_ENCRYPTION_KEY not found" > "$method_dir/encryption_key.txt"
    
    # Create info file
    cat > "$method_dir/README.txt" << EOFL
N8N BACKUP - Full Database Method
Generated: $(date)
Container: $CONTAINER

Files:
- database.sqlite: Complete n8n database
- n8n-full-backup.tar.gz: Full .n8n directory backup
- encryption_key.txt: Encryption key (IMPORTANT!)
- environment.json: Full environment variables

To restore:
1. Stop n8n container
2. Replace database.sqlite file
3. Start n8n container with the same N8N_ENCRYPTION_KEY
EOFL
    
    log "SUCCESS" "Phương pháp 2 hoàn tất ✓"
}

cleanup_old_backups() {
    log "STEP" "Dọn dẹp backups cũ (giữ $RETENTION_DAYS ngày)"
    
    local deleted_count=0
    while IFS= read -r dir; do
        rm -rf "$dir"
        ((deleted_count++))
    done < <(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "[0-9]*" -mtime +$RETENTION_DAYS 2>/dev/null)
    
    if [ $deleted_count -gt 0 ]; then
        log "SUCCESS" "Đã xóa $deleted_count backup cũ"
    else
        log "INFO" "Không có backup cũ cần xóa"
    fi
}

show_backup_summary() {
    local backup_dir=$1
    local total_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "N/A")
    
    echo ""
    print_separator
    echo -e "${BOLD}📊 Backup Summary:${NC}"
    echo -e "   Location:    ${CYAN}$backup_dir${NC}"
    echo -e "   Total Size:  ${CYAN}$total_size${NC}"
    echo -e "   Status:      ${GREEN}✓ COMPLETED${NC}"
    print_separator
    echo ""
}

perform_backup() {
    local date_folder=$(date +'%Y%m%d')
    local time_folder=$(date +'%H%M%S')
    local backup_dir="$BACKUP_BASE_DIR/$date_folder/$time_folder"
    
    print_header
    show_config
    
    log "STEP" "Bắt đầu backup lần thứ $BACKUP_COUNT"
    echo ""
    
    # Create backup directory
    mkdir -p "$backup_dir"
    log "INFO" "Tạo thư mục backup: $backup_dir"
    echo ""
    
    # Find container
    find_n8n_container
    echo ""
    print_separator
    echo ""
    
    # Perform backups
    backup_method_1_cli_export "$backup_dir"
    echo ""
    print_separator
    echo ""
    
    backup_method_2_database "$backup_dir"
    echo ""
    print_separator
    echo ""
    
    # Cleanup
    cleanup_old_backups
    
    # Show summary
    show_backup_summary "$backup_dir"
    
    log "SUCCESS" "Backup hoàn tất! Chờ $BACKUP_INTERVAL_MINUTES phút cho lần backup tiếp theo..."
    echo ""
}

# ============================================
# MAIN EXECUTION
# ============================================

# Create backup directory and log file
mkdir -p "$BACKUP_BASE_DIR"
touch "$LOG_FILE"

# Initial display
print_header
echo -e "${GREEN}${BOLD}🚀 N8N Backup Service Started${NC}"
echo -e "${GREEN}   Service will run continuously and backup every $BACKUP_INTERVAL_MINUTES minutes${NC}"
echo ""
show_config

log "INFO" "N8N Backup Service khởi động"
log "INFO" "Backup sẽ chạy mỗi $BACKUP_INTERVAL_MINUTES phút"
echo ""

# Counter for backup runs
BACKUP_COUNT=0

# Run forever
while true; do
    ((BACKUP_COUNT++))
    
    # Perform backup
    if perform_backup; then
        log "SUCCESS" "Backup lần $BACKUP_COUNT thành công"
    else
        log "ERROR" "Backup lần $BACKUP_COUNT thất bại"
    fi
    
    # Show next backup time
    next_backup_time=$(date -d "+$BACKUP_INTERVAL_MINUTES minutes" +'%H:%M:%S')
    echo -e "${CYAN}⏰ Backup tiếp theo lúc: $next_backup_time${NC}"
    print_separator
    echo ""
    
    # Wait for next backup
    sleep $((BACKUP_INTERVAL_MINUTES * 60))
done
EOF

    chmod +x /usr/local/bin/n8n-backup.sh
    log_success "Đã tạo script backup tại /usr/local/bin/n8n-backup.sh"
}

# Create systemd service
create_systemd_service() {
    log_step "Tạo systemd service..."
    
    cat > /etc/systemd/system/n8n-backup.service << 'EOF'
[Unit]
Description=N8N Automatic Backup Service
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/n8n-backup.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    log_success "Đã tạo systemd service"
}

# Enable and start service
enable_service() {
    log_step "Kích hoạt service..."
    
    systemctl daemon-reload
    log_success "Đã reload systemd daemon"
    
    systemctl enable n8n-backup.service
    log_success "Đã enable service (tự động chạy khi boot)"
    
    systemctl start n8n-backup.service
    log_success "Đã khởi động service"
}

# Show status
show_final_status() {
    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  ${BOLD}CÀI ĐẶT HOÀN TẤT!${NC}                                        ${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}📋 Thông tin service:${NC}"
    echo -e "   Service name:    ${CYAN}n8n-backup.service${NC}"
    echo -e "   Backup location: ${CYAN}/home/minhnc/Desktop/n8n-backup${NC}"
    echo -e "   Interval:        ${CYAN}Mỗi 60 phút${NC}"
    echo ""
    echo -e "${BOLD}🔧 Các lệnh hữu ích:${NC}"
    echo -e "   ${CYAN}sudo systemctl status n8n-backup${NC}     - Xem trạng thái"
    echo -e "   ${CYAN}sudo journalctl -u n8n-backup -f${NC}     - Xem log real-time"
    echo -e "   ${CYAN}sudo systemctl restart n8n-backup${NC}    - Khởi động lại"
    echo -e "   ${CYAN}sudo systemctl stop n8n-backup${NC}       - Dừng service"
    echo -e "   ${CYAN}sudo nano /usr/local/bin/n8n-backup.sh${NC} - Chỉnh sửa cấu hình"
    echo ""
    echo -e "${BOLD}📊 Trạng thái hiện tại:${NC}"
    systemctl status n8n-backup.service --no-pager | head -n 10
    echo ""
    echo -e "${GREEN}✓ Service đang chạy và sẽ tự động backup mỗi giờ!${NC}"
    echo ""
}

# Main installation flow
main() {
    print_header
    
    echo -e "${BOLD}Bắt đầu cài đặt N8N Backup Service...${NC}"
    echo ""
    
    check_root
    check_docker
    check_n8n_container
    
    echo ""
    log_step "Tiến hành cài đặt..."
    echo ""
    
    create_backup_script
    create_systemd_service
    enable_service
    
    sleep 2  # Wait for service to start
    
    show_final_status
}

# Run main
main
