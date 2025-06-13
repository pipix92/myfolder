#!/bin/bash
set -euxo pipefail

#source /venv/main/bin/activate # Mantenuto commentato come concordato
COMFYUI_DIR="/workspace/ComfyUI"
APT_INSTALL="apt-get install -y"

# Packages are installed after nodes so we can fix them...
APT_PACKAGES=(
	"wget" # Essenziale per i download (anche se usiamo curl, è utile averlo)
    "git"  # Essenziale per clonare i nodi
    "curl" # ESSENZIALE per i download con autenticazione
)

PIP_PACKAGES=(
    #"package-1"
    #"package-2"
)

NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/cubiq/ComfyUI_essentials"
)

WORKFLOWS=(

)

CHECKPOINT_MODELS=(
    "https://civitai.com/api/download/models/798204?type=Model&format=SafeTensor&size=full&fp=fp16"
	"https://civitai.com/api/download/models/691639?type=Model&format=SafeTensor&size=full&fp=fp32"
	"https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors?download=true"
)

UNET_MODELS=(
)

LORA_MODELS=(
)

VAE_MODELS=(
	"https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/vae/diffusion_pytorch_model.safetensors?download=true"
)

ESRGAN_MODELS=(
)

CONTROLNET_MODELS=(
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
	# Rendi la directory custom_nodes sicura per Git in modo generico
	git config --global --add safe.directory "/workspace/ComfyUI/custom_nodes/"
	provisioning_get_nodes
    provisioning_get_pip_packages
    provisioning_get_files \
        "${COMFYUI_DIR}/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/unet" \
        "${UNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/lora" \
        "${LORA_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/esrgan" \
        "${ESRGAN_MODELS[@]}"
    provisioning_print_end
}

function provisioning_get_apt_packages() {
	sudo apt-get update
    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
            sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    # Verifica se l'array PIP_PACKAGES non è vuoto
    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
            pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"

        # Rendi la directory specifica del nodo sicura per Git prima di operare su di essa
        git config --global --add safe.directory "${path}"

        if [[ -d "$path" ]]; then # Usa le virgolette per sicurezza
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then # AUTO_UPDATE è una variabile esterna
                printf "Updating node: %s...\n" "${repo}"
                ( cd "$path" && git pull )
                if [[ -e "$requirements" ]]; then # Usa le virgolette per sicurezza
                   pip install --no-cache-dir -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e "$requirements" ]]; then # Usa le virgolette per sicurezza
                pip install --no-cache-dir -r "${requirements}"
            fi
        fi
    done
}

function provisioning_get_files() {
    # Invece di controllare -z $2, controlliamo se ci sono almeno 2 argomenti passati alla funzione
    if [[ "$#" -lt 2 ]]; then
        return 0
    fi
    
    dir="$1"
    mkdir -p "$dir"
    shift # Sposta gli argomenti in modo che $1 diventi il primo URL
    arr=("$@") # Carica tutti gli URL rimanenti nell'array 'arr'
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Application will start now\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    url="https://huggingface.co/api/whoami-v2"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1
    url="https://civitai.com/api/v1/models?hidden=1&limit=1"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Download from $1 URL to $2 file path
function provisioning_download() {
    local auth_header_arg="" # Useremo questo per l'argomento completo -H "Authorization: Bearer ..."
    
    # Estrae il nome del file dall'URL pulendolo da parametri di query
    local filename=$(basename "$1" | cut -d '?' -f 1) 
    
    # Se il nome del file è solo un numero (come 691639 o 798204), aggiungiamo un suffisso .safetensors
    if [[ "$filename" =~ ^[0-9]+$ ]]; then
        # Controlla se l'URL originale contiene un'estensione nota
        if [[ "$1" =~ \.(safetensors|ckpt|pt|zip|rar|7z)$ ]]; then # Aggiunto zip, rar, 7z
            filename="${filename}.${BASH_REMATCH[1]}"
        else
            filename="${filename}.safetensors" # Fallback generico
        fi
    fi

    # Costruisce il percorso completo del file di output
    local output_path="${2}/${filename}"

    # HEADERS COMUNI PER SIMULARE UN BROWSER (UTILI PER VARIE PIATTAFORME)
    # Questi sono gli header che hai testato e che hanno funzionato con curl
    local COMMON_HEADERS=(
        "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:139.0) Gecko/20100101 Firefox/139.0"
        "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        "Accept-Language: en-US,en;q=0.5"
        "Upgrade-Insecure-Requests: 1"
        "Sec-Fetch-Dest: document"
        "Sec-Fetch-Mode: navigate"
        "Sec-Fetch-Site: cross-site"
        "Sec-Fetch-User: ?1"
    )

    local REFERER_HEADER_VAL=""
    local HOST_HEADER_VAL=""

    # Logica per Hugging Face
    if [[ -n "$HF_TOKEN" && "$1" =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_header_arg="-H \"Authorization: Bearer $HF_TOKEN\""
        REFERER_HEADER_VAL="https://huggingface.co/"
        HOST_HEADER_VAL="$(echo "$1" | sed -r 's/https?:\/\///; s/\/.*//')"
        
        # Costruisci la lista di tutti gli header per curl
        local ALL_HEADERS=()
        if [[ -n "${auth_header_arg}" ]]; then ALL_HEADERS+=("${auth_header_arg}"); fi
        if [[ -n "${HOST_HEADER_VAL}" ]]; then ALL_HEADERS+=("-H \"Host: ${HOST_HEADER_VAL}\""); fi
        if [[ -n "${REFERER_HEADER_VAL}" ]]; then ALL_HEADERS+=("-H \"Referer: ${REFERER_HEADER_VAL}\""); fi
        # Aggiungi gli header comuni in modo che Bash li espanda correttamente
        for h in "${COMMON_HEADERS[@]}"; do ALL_HEADERS+=("-H \"$h\""); done

        curl -L "${ALL_HEADERS[@]}" \
             --output "${output_path}" --show-error --progress-bar "$1"
        return $?

    # Logica per Civitai (URL API che richiedono CIVITAI_TOKEN e headers specifici)
    elif [[ -n "$CIVITAI_TOKEN" && "$1" =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_header_arg="-H \"Authorization: Bearer $CIVITAI_TOKEN\"" # Invia il token Civitai
        REFERER_HEADER_VAL="https://civitai.com/"
        HOST_HEADER_VAL="$(echo "$1" | sed -r 's/https?:\/\///; s/\/.*//')"
        
        # Costruisci la lista di tutti gli header per curl (compreso Content-Type)
        local ALL_HEADERS=()
        if [[ -n "${auth_header_arg}" ]]; then ALL_HEADERS+=("${auth_header_arg}"); fi
        if [[ -n "${HOST_HEADER_VAL}" ]]; then ALL_HEADERS+=("-H \"Host: ${HOST_HEADER_VAL}\""); fi
        if [[ -n "${REFERER_HEADER_VAL}" ]]; then ALL_HEADERS+=("-H \"Referer: ${REFERER_HEADER_VAL}\""); fi
        ALL_HEADERS+=("-H \"Content-Type: application/json\"") # Specifico per l'API di Civitai
        # Aggiungi gli header comuni in modo che Bash li espanda correttamente
        for h in "${COMMON_HEADERS[@]}"; do ALL_HEADERS+=("-H \"$h\""); done
        
        curl -L "${ALL_HEADERS[@]}" \
             --output "${output_path}" --show-error --progress-bar "$1"
        return $?

    # Per tutti gli altri URL (inclusi i link Civitai pre-firmati diretti, se usati)
    else
        # Se l'URL è un link Civitai (potrebbe essere un link diretto pre-firmato), imposta Referer e Host
        if [[ "$1" =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
            REFERER_HEADER_VAL="https://civitai.com/"
            HOST_HEADER_VAL="$(echo "$1" | sed -r 's/https?:\/\///; s/\/.*//')\"" # ATTENZIONE: qui c'è un apice extra nell'echo
        fi

        # Chiamata a curl generica (senza header Authorization)
        local ALL_HEADERS=()
        if [[ -n "${HOST_HEADER_VAL}" ]]; then ALL_HEADERS+=("-H \"Host: ${HOST_HEADER_VAL}\""); fi
        if [[ -n "${REFERER_HEADER_VAL}" ]]; then ALL_HEADERS+=("-H \"Referer: ${REFERER_HEADER_VAL}\""); fi
        # Aggiungi gli header comuni in modo che Bash li espanda correttamente
        for h in "${COMMON_HEADERS[@]}"; do ALL_HEADERS+=("-H \"$h\""); done

        curl -L "${ALL_HEADERS[@]}" \
             --output "${output_path}" --show-error --progress-bar "$1"
        return $?
    fi
}

# Allow user to disable provisioning if they started with a script they didnt want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

