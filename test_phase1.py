from core_engine.maker_service import MakerService
from core_engine.config import verify_ffmpeg, verify_onedrive, get_preferred_domains

def run_test():
    print("Running Phase 1 Test...")
    service = MakerService()
    
    # We will test with a specific URL or query.
    # Test with a selection of Indian songs as requested
    test_queries = [
        "Azhagiya Laila (Tamil)",
        "Nattu Nattu RRR (Telugu)",
        "Darshana Hridayam (Malayalam)",
        "Chaleya Jawan (Hindi)",
        "Kaattuchembakam",
        "Raathu Raasan",
        "Main Aur Tu",
        "Sooseki"
    ]
    
    print(f"Songs available for testing: {test_queries}")
    
    for test_query in test_queries:
        print(f"\nTesting with query: {test_query}")
        success = service.process_song(test_query)
        if success:
            print(f"[OK] Completed test for: {test_query}")
        else:
            print(f"[ERROR] Failed test for: {test_query}")
    
    if success:
        print("\n[OK] Phase 1 test completed successfully!")
    else:
        print("\n[ERROR] Phase 1 test failed!")

if __name__ == "__main__":
    import os
    from dotenv import load_dotenv
    
    # Ensure .env is loaded
    env_path = os.path.join(os.path.dirname(__file__), '.env')
    if os.path.exists(env_path):
        load_dotenv(env_path)
        
    # Verify environment first
    if verify_ffmpeg() and verify_onedrive():
        run_test()
    else:
        print("[ERROR] Environment not set up correctly. Fix paths in .env.")
