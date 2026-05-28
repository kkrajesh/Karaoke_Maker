import os
import sys

from duckduckgo_search import DDGS

def test_search(query):
    print(f"Searching: {query}")
    with DDGS() as ddgs:
        for r in ddgs.text(query, max_results=5):
            print(f"  - {r['title']} : {r['href']}")

test_search("Subramanyam For Sale lyrics site:smule.com")
test_search("Subramanyam For Sale lyrics")
