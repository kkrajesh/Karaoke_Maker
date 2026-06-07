from duckduckgo_search import DDGS

def search_duckduckgo_lyrics(query):
    search_terms = [
        f"{query} lyrics site:m3db.com",
        f"{query} lyrics site:msidb.org",
        f"{query} lyrics site:hindilyrics4u.com",
        f"{query} lyrics"
    ]
    
    results = []
    urls_seen = set()
    
    with DDGS() as ddgs:
        for search_term in search_terms:
            print(f"Searching: {search_term}")
            try:
                # Get max 5 results per search term
                ddgs_results = ddgs.text(search_term, max_results=5)
                for r in ddgs_results:
                    href = r.get('href', '')
                    title = r.get('title', '')
                    if href and href not in urls_seen:
                        urls_seen.add(href)
                        results.append({"title": title, "url": href})
            except Exception as e:
                print(f"Error for {search_term}: {e}")
                
    return results

print(search_duckduckgo_lyrics("Chundathu chethipoo"))
