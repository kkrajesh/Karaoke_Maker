import os
import requests
from dotenv import load_dotenv

# Path to the .env file in the project root
env_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), '.env')

# Load the environment variables
if os.path.exists(env_path):
    load_dotenv(env_path)
else:
    print(f"[!] .env file not found at {env_path}.")
    print("   Make sure to copy .env.example to .env and configure it.")
    
    # Fallback to .env.example just for testing the script structure
    example_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), '.env.example')
    if os.path.exists(example_path):
        load_dotenv(example_path)

def verify_ffmpeg():
    ffmpeg_path = os.getenv("FFMPEG_PATH")
    if not ffmpeg_path:
        print("[ERROR] FFMPEG_PATH is not set in the environment.")
        return False
    
    if os.path.exists(ffmpeg_path):
        print(f"[OK] FFmpeg found at: {ffmpeg_path}")
        return True
    else:
        print(f"[ERROR] FFmpeg NOT found at: {ffmpeg_path}")
        return False

def verify_hotzone():
    hotzone_path = os.getenv("AI_HOTZONE")
    if not hotzone_path:
        print("[ERROR] AI_HOTZONE is not set in the environment.")
        return False
    
    if os.path.exists(hotzone_path):
        print(f"[OK] AI Hot Zone found at: {hotzone_path}")
        return True
    else:
        # Auto-create if not exists
        try:
            os.makedirs(hotzone_path, exist_ok=True)
            print(f"[OK] AI Hot Zone created at: {hotzone_path}")
            return True
        except Exception as e:
            print(f"[ERROR] Failed to create AI Hot Zone at: {hotzone_path}. Error: {e}")
            return False

def get_preferred_domains():
    domains_str = os.getenv("PREFERRED_AUDIO_DOMAINS", "")
    if domains_str:
        domains = [d.strip() for d in domains_str.split(",") if d.strip()]
        print(f"[OK] Preferred Audio Domains: {', '.join(domains)}")
        return domains
    else:
        print("[INFO] No Preferred Audio Domains specified. Will default to YouTube.")
        return []

def verify_llm_connectivity():
    llm_base_url = os.getenv("LLM_BASE_URL")
    if not llm_base_url:
        print("[ERROR] LLM_BASE_URL is not set in the environment.")
        return False
    
    # Most local LLMs (Ollama, LM Studio) provide an OpenAI-compatible /models endpoint
    models_url = f"{llm_base_url}/models"
    print(f"[WAIT] Testing LLM connectivity at: {models_url} ...")
    
    try:
        response = requests.get(models_url, timeout=5)
        if response.status_code == 200:
            print("[OK] Successfully connected to Local LLM!")
            try:
                data = response.json()
                models = data.get("data", [])
                if models:
                    print("   Available Models:")
                    for model in models:
                        print(f"   - {model.get('id')}")
                else:
                    print("   Connected, but no models found or different response format.")
            except ValueError:
                print("   Connected, but response is not JSON.")
            return True
        else:
            print(f"[ERROR] Failed to connect. HTTP Status Code: {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"[ERROR] Failed to connect to Local LLM. Error: {e}")
        return False

if __name__ == "__main__":
    print("=====================================")
    print("  Karaoke Maker - Phase 0 Self-Test  ")
    print("=====================================\n")
    
    ffmpeg_ok = verify_ffmpeg()
    hotzone_ok = verify_hotzone()
    preferred_domains = get_preferred_domains()
    
    print("-" * 37)
    llm_ok = verify_llm_connectivity()
    
    print("\n=====================================")
    if ffmpeg_ok and llm_ok and hotzone_ok:
        print("[DONE] Phase 0 Verification Complete. All systems go!")
    else:
        print("[!] Phase 0 Verification Completed with issues. Please update your .env file.")
    print("=====================================")
