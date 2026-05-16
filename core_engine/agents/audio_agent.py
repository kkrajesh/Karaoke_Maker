import os
import json
from openai import OpenAI

class AudioAgent:
    def __init__(self):
        base_url = os.getenv("LLM_BASE_URL", "http://localhost:1234/v1")
        # For local LLMs, API key is usually not required, but OpenAI client needs something.
        api_key = os.getenv("LLM_API_KEY", "not-needed")
        
        self.client = OpenAI(base_url=base_url, api_key=api_key)
        self.model = os.getenv("LLM_MODEL", "local-model") # LM Studio often ignores this

    def pick_best_source(self, query, search_results):
        """
        Asks the Local LLM to pick the best audio source from a list of search results.
        search_results is a list of dicts: [{"title": "...", "url": "..."}, ...]
        Returns the winning URL and the reason.
        """
        if not search_results:
            return None, "No results provided"
            
        if len(search_results) == 1:
            return search_results[0]["url"], "Only one result available"

        # Format results for the prompt
        results_text = ""
        for i, res in enumerate(search_results):
            results_text += f"[{i}] Title: {res['title']}\n    URL: {res['url']}\n"

        prompt = f"""
You are an expert music archivist. I am building a high-fidelity karaoke track.
The user requested the song: "{query}"

Here are the top search results:
{results_text}

Your task:
1. Identify the result that is the ORIGINAL STUDIO version of the requested song.
2. Ensure the language and movie (if specified in the query) match the title.
3. STRICTLY AVOID "Live", "Cover", "Remix", "8D", "Acoustic", or "Reaction" videos unless explicitly requested.
4. Output a JSON object with two keys:
   "index": the integer index of the best result (e.g., 0).
   "reason": a short string explaining why you chose it and rejected others.

Output ONLY valid JSON. No markdown formatting, no other text.
"""

        try:
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": "You are a precise JSON-outputting agent."},
                    {"role": "user", "content": prompt}
                ],
                temperature=0.1,
                max_tokens=150
            )
            
            content = response.choices[0].message.content.strip()
            
            # Clean up potential markdown formatting if the LLM misbehaves
            if content.startswith("```json"):
                content = content[7:]
            if content.startswith("```"):
                content = content[3:]
            if content.endswith("```"):
                content = content[:-3]
                
            data = json.loads(content.strip())
            best_idx = data.get("index", 0)
            reason = data.get("reason", "No reason provided")
            
            # Ensure index is in bounds
            if not isinstance(best_idx, int) or best_idx < 0 or best_idx >= len(search_results):
                best_idx = 0
                
            return search_results[best_idx]["url"], reason
            
        except Exception as e:
            # Fallback to the first result if the LLM fails or is offline
            print(f"[WARN] AudioAgent LLM failed: {e}. Falling back to first result.")
            return search_results[0]["url"], f"LLM Error: {e}"
