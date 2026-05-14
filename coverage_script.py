import json
import plistlib
import sys

def load_tsv(path):
    items = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                items.append(line)
    return items

def load_plist_as_dict(path):
    # vin.plist: array of dicts with 'phrase' and 'shortcut'
    with open(path, 'rb') as f:
        data = plistlib.load(f)
    phrase_to_readings = {}
    for entry in data:
        phrase = entry.get('phrase')
        reading = entry.get('shortcut')
        if phrase and reading:
            if phrase not in phrase_to_readings:
                phrase_to_readings[phrase] = set()
            phrase_to_readings[phrase].add(reading)
    return phrase_to_readings

def load_json_as_dict(path):
    # JSON: reading -> [phrases]
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    phrase_to_readings = {}
    for reading, phrases in data.items():
        for phrase in phrases:
            if phrase not in phrase_to_readings:
                phrase_to_readings[phrase] = set()
            phrase_to_readings[phrase].add(reading)
    return phrase_to_readings

def main():
    vin2_file = 'references/vin2.tsv'
    plist_file = 'references/vin.plist'
    second_vocab_file = 'tmp/ÉcrituSecondVocab.json'
    premier_vocab_file = 'tmp/ÉcrituPremierVocab.json'

    vin2_items = load_tsv(vin2_file)
    unique_vin2 = sorted(list(set(vin2_items)))

    plist_dict = load_plist_as_dict(plist_file)
    second_dict = load_json_as_dict(second_vocab_file)
    premier_dict = load_json_as_dict(premier_vocab_file)

    match_plist = [item for item in unique_vin2 if item in plist_dict]
    match_second = [item for item in unique_vin2 if item in second_dict]
    match_premier = [item for item in unique_vin2 if item in premier_dict]

    union_covered = [item for item in unique_vin2 if item in plist_dict or item in second_dict or item in premier_dict]
    uncovered = [item for item in unique_vin2 if item not in plist_dict and item not in second_dict and item not in premier_dict]

    print(f"1) Unique items in vin2.tsv: {len(unique_vin2)}")
    print(f"2) Exact matches from vin.plist: {len(match_plist)}")
    print(f"3) Exact matches from SecondVocab: {len(match_second)}")
    print(f"4) Exact matches from PremierVocab: {len(match_premier)}")
    print(f"5) Union coverage: {len(union_covered)}")
    print(f"6) Top 30 uncovered terms:")
    for item in uncovered[:30]:
        print(f"   - {item}")

    print(f"\nSource dictionary sizes (number of phrases):")
    print(f"   vin.plist: {len(plist_dict)}")
    print(f"   SecondVocab: {len(second_dict)}")
    print(f"   PremierVocab: {len(premier_dict)}")

    # Check for duplicate conflicting readings for same phrase across sources
    print("\nDuplicate conflicting readings for same phrase across sources:")
    conflict_count = 0
    # Combine sets of readings for each phrase
    all_phrases = set(plist_dict.keys()) | set(second_dict.keys()) | set(premier_dict.keys())
    for phrase in sorted(list(all_phrases)):
        readings = set()
        if phrase in plist_dict: readings.update(plist_dict[phrase])
        if phrase in second_dict: readings.update(second_dict[phrase])
        if phrase in premier_dict: readings.update(premier_dict[phrase])
        
        if len(readings) > 1:
            conflict_count += 1
            if conflict_count <= 20: # Limit output to top 20 conflicts
                print(f"   Phrase: {phrase}, Readings: {sorted(list(readings))}")
    
    if conflict_count > 20:
        print(f"   ... and {conflict_count - 20} more conflicts.")
    elif conflict_count == 0:
        print("   None found.")

if __name__ == "__main__":
    main()
