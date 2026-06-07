import requests
from bs4 import BeautifulSoup
import urllib.parse

def search_m3db(query):
    print(f"Searching m3db for {query}")
    url = f"https://m3db.com/search/node/{urllib.parse.quote(query)}"
    headers = {'User-Agent': 'Mozilla/5.0'}
    results = []
    try:
        response = requests.get(url, headers=headers, timeout=5)
        print(f"M3DB status: {response.status_code}")
        if response.status_code == 200:
            soup = BeautifulSoup(response.text, 'html.parser')
            # Look for search results links
            for a in soup.find_all('a'):
                href = a.get('href', '')
                if '/lyric/' in href:
                    full_url = href if href.startswith('http') else 'https://m3db.com' + href
                    results.append({"title": a.text.strip(), "url": full_url})
    except Exception as e:
        print(e)
    return results

print(search_m3db("Chundathu chethipoo"))
