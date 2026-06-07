import requests
from bs4 import BeautifulSoup
import urllib.parse

def search_yahoo_lyrics(query):
    search_terms = [
        f"{query} lyrics site:m3db.com",
        f"{query} lyrics site:msidb.org",
        f"{query} lyrics site:hindilyrics4u.com",
        f"{query} lyrics"
    ]
    
    results = []
    urls_seen = set()
    
    for search_term in search_terms:
        print(f"Searching Yahoo: {search_term}")
        url = 'https://search.yahoo.com/search?p=' + urllib.parse.quote(search_term)
        response = requests.get(
            url, 
            headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'},
            timeout=5
        )
        print(f"Status Code: {response.status_code}")
        if response.status_code == 200:
            soup = BeautifulSoup(response.text, 'html.parser')
            for div in soup.find_all('div', class_='compTitle'):
                a = div.find('a')
                if a:
                    href = a.get('href', '')
                    title = a.text.strip()
                    if href and href not in urls_seen:
                        urls_seen.add(href)
                        results.append({"title": title, "url": href})
    return results

print(search_yahoo_lyrics("Chundathu chethipoo"))
