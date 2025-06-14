#!/bin/bash
set -euxo pipefail

source /venv/main/bin/activate # Mantenuto commentato come concordato
COMFYUI_DIR="/workspace/ComfyUI"
APT_INSTALL="apt-get install -y"

# Packages are installed after nodes so we can fix them...
APT_PACKAGES=(
	"wget" # Essenziale per i download (anche se usiamo curl, è utile averlo)
    "git"  # Essenziale per clonare i nodi
    "curl" # ESSENZIALE per i download con autenticazione
	"git-lfs"

)

PIP_PACKAGES=(
    "piexif"
    "matplotlib"
	"huggingface-hub"
)

NODES=(
    # --- Gestione e UI ---
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/rgthree/rgthree-comfy"

    # --- Suite di Nodi Principali ---
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/ltdrdata/was-node-suite-comfyui" # Nota: Corrisponde alla tua cartella 'was-ns'
    "https://github.com/wallish77/wlsh_nodes"
    "https://github.com/kijai/ComfyUI-KJNodes"

    # --- Preprocessori e Utility Video ---
    "https://github.com/Fannovel16/comfyui_controlnet_aux"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/kijai/ComfyUI-HunyuanVideoWrapper" # Nota: Corrisponde a 'comfyui-hunyuanvideowrapper'
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

DIFFUSERS_MODELS=(
	"https://huggingface.co/black-forest-labs/FLUX.1-dev"
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
	git lfs install
	# Rendi la directory custom_nodes sicura per Git in modo generico
	git config --global --add safe.directory "/workspace/ComfyUI/custom_nodes/"
	provisioning_get_nodes
	provisioning_get_diffusers
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

function provisioning_get_diffusers() {
    if [[ ${#DIFFUSERS_MODELS[@]} -eq 0 ]]; then
        return
    fi

    printf "Comincio il download dei modelli Diffusers con huggingface-cli...\n"
    for repo in "${DIFFUSERS_MODELS[@]}"; do
        # Estrae l'ID del repository (es. black-forest-labs/FLUX.1-dev)
        repo_id=$(echo "$repo" | sed 's|https://huggingface.co/||')
        # Estrae il nome della cartella finale (es. FLUX.1-dev)
        dir_name="${repo##*/}"
        path="${COMFYUI_DIR}/models/diffusers/${dir_name}"

        if [[ -d "$path" ]]; then
            printf "Modello Diffusers '%s' già presente. Salto.\n" "${dir_name}"
        else
            printf "Scaricando il modello Diffusers: %s...\n" "${repo_id}"
            # Usa il comando ufficiale di Hugging Face, è molto più robusto di git clone per i modelli
            huggingface-cli download "${repo_id}" --local-dir "${path}" --local-dir-use-symlinks False
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
    local url="$1"
    local dir="$2"
    
    # Estrae il nome del file dall'URL pulendolo da parametri di query
    local filename=$(basename "$url" | cut -d '?' -f 1)
    
    # Se il nome del file è solo un numero (es. da Civitai), aggiunge .safetensors
    if [[ "$filename" =~ ^[0-9]+$ ]]; then
        filename="${filename}.safetensors"
    fi

    local output_path="${dir}/${filename}"

    # Headers comuni per simulare un browser
    local -a common_headers=(
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"
        -H "Accept-Language: en-US,en;q=0.5"
    )

    # Imposta gli header di autorizzazione se i token sono presenti
    if [[ "$url" =~ huggingface\.co && -n "$HF_TOKEN" ]]; then
        common_headers+=(-H "Authorization: Bearer $HF_TOKEN")
    elif [[ "$url" =~ civitai\.com && -n "$CIVITAI_TOKEN" ]]; then
        common_headers+=(-H "Authorization: Bearer $CIVITAI_TOKEN")
    fi

    # Esegue il download con curl, che è più robusto per gli header
    printf "Downloading %s to %s\n" "${filename}" "${dir}"
    curl -L --progress-bar "${common_headers[@]}" -o "${output_path}" -- "$url"
    printf "Download of %s completed.\n" "${filename}"
}

# Allow user to disable provisioning if they started with a script they didnt want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

