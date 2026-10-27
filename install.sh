#!/usr/bin/env bash

## v20.02
## 20260810
## Odoo OXP 2026 - Master=20

set -Eeuo pipefail
DEBUG_FILE="/var/log/odoo_install.debug"
LOG="/var/log/odoo_installation.log"
DB_NAME=""
ALIAS_NAME="odoo-localDB"
MANAGER_SHORTCUT_PATH="/home/odoo/Desktop/odoo_local_databases_manager.desktop"
ODOO_SHORTCUT_PATH="/home/odoo/Desktop/odoo_launcher.desktop"
USER_PASSWORD=""
POSTGRES_VERSION=18
ODOO_REPO_PATH="/home/odoo/odoo"
ODEV_REPO_PATH="/home/odoo/odev"
# https://www.odoo.com/documentation/master/administration/on_premise/source.html#postgresql

odoorc_gist_path="https://gist.githubusercontent.com/Abridbus/a4c1ada1e8c61c04ab68cc8ddbb827b1/raw/4614022d0c21bbc02f35254d59c5cefcdbedb12d/.odoorc"

RED=$'\e[31m'
GREEN=$'\e[32m'
BLUE=$'\e[34m'
ENDCOLOR=$'\e[0m'

create_log_file() {
	# Create a LOG file a each run
	echo "$USER_PASSWORD" | sudo -v -S >/dev/null 2>&1
	sudo touch "$LOG" "$DEBUG_FILE"
	sudo chown "$USER" "$LOG"
	sudo chown "$USER" "$DEBUG_FILE"
	: >"$LOG"
	sudo -k
}

# Put the outuput of heavy cmd into LOG  (often for apt)
run() { "$@" >>"$LOG" 2>&1; }

run_sudo() { echo "$USER_PASSWORD" | sudo -S -k "$@" >>"$LOG" 2>&1; }

# catch if the script crash
trap 'echo; echo "FAILED (line $LINENO). Last lines of $LOG:"; tail -n 15 "$LOG"' ERR

# Echo + in debug file
log() {
	echo -e "$*"
	echo "$(date) - $*" >>"$DEBUG_FILE"
}

ok() { log "${GREEN}[  OK  ] $*${ENDCOLOR}"; }

fail() { log "${RED}[ MISS ] $*${ENDCOLOR}"; }

exists() {
	if [[ -e "$1" ]]; then
		ok "$1"
	else
		fail "$1"
	fi
}

inputdata() {
	#clean stdin  buffer
	while read -r -t 0; do read -r; done
	read -r -p "$*" response
	echo "${response}"
}

# Check the repo and print the branch
repo_check() {
	if [[ -d "$1/.git" ]]; then
		ok "$1 ($(git -C "$1" rev-parse --abbrev-ref HEAD))"
	else
		fail "$1"
	fi
}

have() { command -v "$1" >/dev/null 2>&1; } # Check a cmd

install_cmd() {
	local cmd="$1" pkg="${2:-$1}"
	if have "$cmd"; then
		log "${BLUE}  $cmd already installed.${ENDCOLOR}"
	else
		log "${BLUE}  Installing $pkg ...${ENDCOLOR}"
		run_sudo apt-get install -y "$pkg"
		have "$cmd" || log "${RED}  WARNING: $cmd install failed${ENDCOLOR}"
	fi
}

ask_password() {
	while read -r -t 0; do read -r; done
	while ! (echo "$USER_PASSWORD" | sudo -S -k -v >/dev/null 2>&1); do
        USER_PASSWORD=$(systemd-ask-password "Enter your password:")
		echo ""
	done
}

check_ssh_key() {
	local user_gram
	local ssh_known_hosts_path="/home/odoo/.ssh/known_hosts"
	local ssh_key_path="/home/odoo/.ssh/id_ed25519"
	local ssh_pub_key_path="/home/odoo/.ssh/id_ed25519.pub"
	user_gram="$(cut -d '-' -f 1 </etc/hostname)"
	if [[ -f "${ssh_pub_key_path}" ]]; then
		log "${BLUE}There is already an exisiting SSH key on this system(${ssh_key_path}) ${ENDCOLOR}"
		log "${BLUE}Please make sure the public key below is referenced in your GitHub profile [https://github.com/settings/keys]:${ENDCOLOR}"
		log "$(<$ssh_pub_key_path)"
	else
		log "${BLUE}SSH key not found. Generating new ed25519 SSH key for '${user_gram}@odoo.com'.${ENDCOLOR}"
		log "${BLUE}Path to add the key: ${ssh_key_path}${ENDCOLOR}"
		run ssh-keygen -t ed25519 -C "${user_gram}@odoo.com" -f "$ssh_key_path"
		log "${BLUE}Please add the public key below to your GitHub profile [https://github.com/settings/keys]:${ENDCOLOR}"
		echo "$(<$ssh_pub_key_path)"
	fi
	log "${BLUE}Adding Github fingerprints to known_hosts file if needed${ENDCOLOR}"
	if [[ -f "${ssh_known_hosts_path}" ]] && grep -qw "github.com" $ssh_known_hosts_path; then
		log "${BLUE}Fingerprint already present, nothing to do${ENDCOLOR}"
	else
		curl --silent https://api.github.com/meta | jq --raw-output '"github.com "+.ssh_keys[]' >>$ssh_known_hosts_path #https://docs.github.com/en/rest/meta/meta?apiVersion=2026-03-10#get-github-meta-information
	fi
	while true; do
		if git ls-remote git@github.com:odoo/enterprise.git HEAD >/dev/null 2>&1; then
			log "${BLUE}GitHub SSH access validated${ENDCOLOR}"
			break
        else
            log "${BLUE}No GitHub SSH access."
		fi
		read -r "${GREEN}Press enter when your public key was added to your GitHub account... ${ENDCOLOR}"
	done
}

check_ubuntu() {
	. /etc/os-release # Get ID and verison varialbe
	log "${BLUE}System: $ID $VERSION_ID (user $USER)${ENDCOLOR}"
	if [[ "$ID" != "ubuntu" ]]; then
		log "${RED}ERROR: expected Ubuntu, found: $ID. OS not supported. Exit...${ENDCOLOR}"
		exit 1
	fi
	if [[ "$VERSION_ID" != "24.04" && "$VERSION_ID" != "26.04" ]]; then
		log "${RED}Your installation variant is not supported, expected version: '24.04' or '26.04' found: $VERSION_ID.${ENDCOLOR}"
		exit 1
	fi
	if [[ "${USER}" != "odoo" ]]; then
		log "${RED}ERROR: expected 'odoo' username, only OSes provided by Odoo are supported. Exit...${ENDCOLOR}"
		exit 1
	fi
}

check_python() {
	have python3 || {
		log "${RED}python3 not found.${ENDCOLOR}"
		exit 1
	}
	log "Python: $(python3 --version)"
	python3 -c 'import sys; sys.exit(sys.version_info < (3, 12))' ||
		{
			log "${RED}ERROR : need 3.12+.${ENDCOLOR}"
			exit 1
		}
}

check_cmd() {
	local cmd="$1"
	if ! have "$cmd"; then
		fail "$cmd not installed"
		return
	fi
	local out
	out=$("$cmd" --version 2>&1 | head -1)
	log ""
	ok "$cmd Installed"
	log "VERSION : $out"
	log ""
}

install_wkhtmltopdf() {
	wkhtmltopdf --version 2>/dev/null | grep -q "with patched qt" && return 0
	log "${BLUE}  Installing wkhtmltopdf (patched qt) ...${ENDCOLOR}"
	run_sudo dpkg -r wkhtmltox || true
	run curl -sSL https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb -o /tmp/wkhtml.deb
	run_sudo apt-get -y install --no-install-recommends --fix-missing /tmp/wkhtml.deb
	rm -f /tmp/wkhtml.deb
}

install_phonenumbers(){
	log "${BLUE}  Installing python3-phonenumbers ...${ENDCOLOR}"
	run sudo apt-get install -y python3-phonenumbers
	if python3 -c "import phonenumbers" &> /dev/null ; then
		ok "python3-phonenumbers installed"
	else
		fail "python3-phonenumbers failed to install"
	fi
}

install_pgvector() {
	log "${BLUE}  Installing pgvector ...${ENDCOLOR}"
	run sudo apt-get install -y postgresql-common
    if [ ! -f /etc/apt/sources.list.d/pgdg.sources ]; then # TODO test it
        sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
    fi
	run sudo apt-get install -y "postgresql-${POSTGRES_VERSION}-pgvector"
	echo 'trusted = true' | sudo tee -a "$(pg_config --sharedir)/extension/vector.control"
}

install_rtlcss() {
	answer=$(inputdata "${GREEN}Need RTLCSS ? It's for the Odoo interface for right-to-left languages (Arabic, Hebrew). Only needed if you work with those [y/N]: ${ENDCOLOR}")
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		install_cmd npm
		log "${BLUE}  Installing rtlcss ...${ENDCOLOR}"
		run_sudo npm install -g rtlcss
		answer=$(inputdata "${GREEN}Remove NPM ? [y/N]: ${ENDCOLOR}")
		if [[ "$answer" =~ ^[Yy]$ ]]; then
			log "${BLUE}  Removing npm ...${ENDCOLOR}"
			run_sudo apt-get -y remove npm
		fi
	fi
}

install_virtualenv() {
    command -v uv >/dev/null && uv install virtualenv && return 0
    command -v pipx >/dev/null || sudo apt install -y pipx
    pipx install virtualenv
}

install_deps() {
	log "${BLUE}Installing system dependencies ...${ENDCOLOR}"
	install_cmd git
	install_cmd curl
	install_cmd psql postgresql-18
	install_phonenumbers
	install_wkhtmltopdf
	install_pgvector
    install_virtualenv
	log "${BLUE}Dependencies ready.${ENDCOLOR}"
}

check_deps() {
	clear
	log "--- 1. System ---"
	. /etc/os-release
	log "OS       : $ID $VERSION_ID"
	log "User     : $USER"
	log "--- 2. Python ---"
	check_cmd python3
	log "--- 3. Dependencies ---"
	check_cmd git
	check_cmd curl
	check_cmd psql
	check_cmd wkhtmltopdf
	log "--- 4. Folders ---"
	exists "$ODOO_REPO_PATH"
	repo_check "$ODOO_REPO_PATH/odoo"
	repo_check "$ODOO_REPO_PATH/enterprise"
	repo_check "$ODOO_REPO_PATH/design-themes"
	repo_check "$ODOO_REPO_PATH/industry"
	log "--- 6. Extra dependencies ---"
	check_cmd rtlcss
	check_cmd mailcatcher
	echo "Report saved to $DEBUG_FILE"
}

debinstall_sh() {
    echo "${BLUE} Installing required packages: ${ENDCOLOR}"
	run_sudo "${ODOO_REPO_PATH}/odoo/setup/debinstall.sh"
}

postgresql_setup() {
	log "${BLUE}Configuring PostgreSQL ...${ENDCOLOR}"
	echo "$USER_PASSWORD" | sudo -S systemctl enable --now postgresql
	if sudo -u postgres psql -t -c '\du' | cut -f 1 -d \| | grep -qw odoo; then
		log "${BLUE} Odoo PostgreSQL User already exists. Skipping.${ENDCOLOR}"
	else
		run_sudo sudo -u postgres createuser -d -R -S odoo
	fi
	run_sudo sudo -u postgres psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS vector;" # ALL FUTUR DB will get it
}

setup_odoorc() {
	log "${GREEN}Fetching .odoorc configuration ...${ENDCOLOR}"
	run curl -fsSL -o /home/odoo/.odoorc "${odoorc_gist_path}"
}

install_mailcatcher() {
	echo "Mailcatcher is a local mailing solution. If you want to send email and visual them without a mail server"
	answer=$(inputdata "${GREEN}Do you want to install it [y/N]: ${ENDCOLOR}")
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		have mailcatcher && return 0
		log "${BLUE}  Installing MailCatcher ...${ENDCOLOR}"
		run_sudo apt-get install -y ruby ruby-dev
		run_sudo gem install mailcatcher
	fi
}

create_database() {
	local pattern="^[0-9a-zA-Z_-]{1,60}$"
	while :; do
		DB_NAME=$(inputdata "${GREEN}Name of your database you want to create (leave empty to create default one named odoo): ${ENDCOLOR}")
		[[ -z "$DB_NAME" ]] && DB_NAME="odoo"
		[[ $DB_NAME =~ $pattern ]] && break
		echo "${RED}Invalid name: only a-z, A-Z, 0-9, _ and - allowed.${ENDCOLOR}"
	done
	if [[ -n "$DB_NAME" ]]; then
		cd "$ODOO_REPO_PATH/odoo"
		log "${BLUE}Creating database '$DB_NAME' (a few minutes) ...${ENDCOLOR}"
		run python3 odoo-bin -c /home/odoo/.odoorc -d "$DB_NAME" -i base --stop-after-init
	fi
}

clean_database() {
	echo "${RED} This db that will be DELETED: '$DB_NAME' ${ENDCOLOR}"
	sudo -u postgres psql -Atc "SELECT datname FROM pg_database where name ilike '$DB_NAME';"
	sudo -u postgres dropdb "$DB_NAME"
	sudo rm -rf "/home/odoo/.local/share/Odoo/filestore/${DB_NAME}"
}

set_expiration_date() {
	log "${BLUE}Setting expiration date to 2998.${ENDCOLOR}"
	psql -d "$DB_NAME" >>"$LOG" 2>&1 <<-'SQL'
		INSERT INTO ir_config_parameter (key, value)
		VALUES ('database.expiration_date', '2998-05-07 13:16:50')
		ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
		DELETE FROM ir_config_parameter WHERE key = 'database.expiration_reason';
	SQL
	log "${BLUE}Expiration date set on '$DB_NAME'.${ENDCOLOR}"
}

check_memory() {
	log "${BLUE}Checking system memory.${ENDCOLOR}"
	# check laptop memory, if <= 16G change some github params to prevent clone error "fatal: fetch-pack: Invalid index-pack output"
	if [ "$(awk '/MemTotal/ {print $2}' /proc/meminfo)" -le 16777216 ]; then
		run git config --global pack.threads 1
		run git config --global http.postBuffer 524288000
		log "${BLUE}GIT config changed to increase HTTP POST buffer.${ENDCOLOR}"
	fi
}

add_alias() { # TODO find a way to add this alias in the terminal used by the user -> add a small wrapper in PATH
	if grep -qw $ALIAS_NAME /home/odoo/.bashrc; then
		log "${BLUE}Alias already exists. Skipping.${ENDCOLOR}"
	else
		log "${BLUE}Adding a bash alias${ENDCOLOR}"
		echo "alias $ALIAS_NAME='cd $ODOO_REPO_PATH/odoo; python3 ./odoo-bin'" >>/home/odoo/.bashrc
	fi
}

add_desktop_shortcuts() {
	log "${BLUE}Adding desktop shortcuts${ENDCOLOR}"
	{
		echo "[Desktop Entry]"
		echo "Icon=text-html"
		echo "Name=Odoo - Local DB manager"
		echo "Type=Application"
		echo "Exec= xdg-open http://localhost:8069/web/database/manager"
	} >"${MANAGER_SHORTCUT_PATH}"

	{
		echo "[Desktop Entry]"
		echo "Exec=$ODOO_REPO_PATH/odoo/odoo-bin"
		echo "GenericName=Launch Odoo Local DB"
		echo "Icon=system-run"
		echo "Name=Launch Odoo Local DB"
		echo "StartupNotify=true"
		echo "Terminal=true"
		echo "Type=Application"
	} >"$ODOO_SHORTCUT_PATH"
}

install_odev() {
    if [ -d "$ODEV_REPO_PATH" ]; then
        log "${BLUE}Odev repository already exists. Updating it...${ENDCOLOR}"
        cd "$ODEV_REPO_PATH"
        git pull
    else
        git clone --progress "git@github.com:odoo-odev/odev.git" "$ODEV_REPO_PATH" 2>&1 | tee -a "$LOG"
        cd "$ODEV_REPO_PATH"
    fi
    ./install.sh
    odev setup
    log "${BLUE}Odev is installed ! Installing plugins..${ENDCOLOR}"
    odev plugin --enable odoo-odev/odev-plugin-ai
}

install_deadsnake_ppa() {
    if compgen -G '/etc/apt/sources.list.d/deadsnakes-ubuntu-ppa-*.sources' > /dev/null; then
        log "${BLUE}Deadsnakes PPA is already installed. Skipping..${ENDCOLOR}"
        return 0
    fi
    run_sudo add-apt-repository ppa:deadsnakes/ppa -y
    run_sudo apt update
}

odoo_local_installation() {
	clear
	check_memory
	check_ubuntu
	check_python
	install_deps
	check_ssh_key
    install_rtlcss      # right-to-left
    install_mailcatcher # mail
	postgresql_setup
	setup_odoorc # Prior create_database to add enterprise in path
	create_database
	set_expiration_date
	add_alias
	add_desktop_shortcuts
    install_deadsnake_ppa
    install_odev
}

if [ $# -eq 0 ]; then
	start_time=$(date +%s)
    ask_password
    create_log_file
    odoo_local_installation
	stop_time=$(date +%s)
	run_time=$((stop_time - start_time))
	log "Run duration: ${run_time}s"
elif [ "$1" == "check" ]; then
    check_deps
fi
