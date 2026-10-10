"""App Store Connect, through its API: the product page's text, screenshots and previews,
the build on the version. Needs ASC_KEY_PATH (the .p8 of a team key with the App Manager
role, kept in ~/.appstoreconnect/private_keys), ASC_KEY_ID and ASC_ISSUER_ID; PyJWT.
The Duo sets are left alone (see the README).
    python3 asc.py state                 what the version has now
    python3 asc.py text                  set the subtitle, promotional text, description and keywords from metadata.md
    python3 asc.py screenshots           replace the iPhone 6.9, 6.3 and iPad 13 sets
    python3 asc.py previews              replace the iPhone 6.9 and iPad 13 previews
    python3 asc.py build 8               wait for build 8 to process, then put it on the version
"""
import hashlib, json, os, sys, time, urllib.error, urllib.request
import jwt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = '6818395717'
API = 'https://api.appstoreconnect.apple.com'
SETS = {'APP_IPHONE_67': 'iPhone-6.9', 'APP_IPHONE_61': 'iPhone-6.3', 'APP_IPAD_PRO_3GEN_129': '.'}
PREVIEWS = {'IPHONE_67': 'previews/iPhone-6.9.mp4', 'IPAD_PRO_3GEN_129': 'previews/iPad-13.mp4'}
KEY, KID, ISS = os.environ['ASC_KEY_PATH'], os.environ['ASC_KEY_ID'], os.environ['ASC_ISSUER_ID']


def token():
    now = int(time.time())
    return jwt.encode({'iss': ISS, 'iat': now, 'exp': now + 900, 'aud': 'appstoreconnect-v1'},
                      open(KEY).read(), algorithm='ES256', headers={'kid': KID, 'typ': 'JWT'})


def call(method, path, body=None):
    req = urllib.request.Request(API + path, data=json.dumps(body).encode() if body is not None else None, method=method)
    req.add_header('Authorization', 'Bearer ' + token())
    if body is not None:
        req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req) as r:
            text = r.read()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        print(method, path, e.code, e.read()[:1200].decode(errors='replace'))
        raise


def put(op, chunk):
    req = urllib.request.Request(op['url'], data=chunk, method=op['method'])
    for h in op['requestHeaders']:
        req.add_header(h['name'], h['value'])
    with urllib.request.urlopen(req) as r:
        r.read()


def version():
    data = call('GET', f'/v1/apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=10')['data']
    live = [v for v in data if v['attributes']['appStoreState'] not in ('READY_FOR_SALE', 'REPLACED_WITH_NEW_VERSION', 'REMOVED_FROM_SALE')]
    v = (live or data)[0]
    print('version', v['attributes']['versionString'], v['attributes']['appStoreState'], v['id'])
    return v['id']


def localization(vid):
    data = call('GET', f'/v1/appStoreVersions/{vid}/appStoreVersionLocalizations')['data']
    loc = next((l for l in data if l['attributes']['locale'] == 'en-US'), data[0])
    print('localization', loc['attributes']['locale'], loc['id'])
    return loc['id']


def upload(kind, set_kind, set_id, path):
    """One file into a screenshot or preview set: reserved, sent in the parts asked for, committed."""
    data = open(path, 'rb').read()
    name = os.path.basename(path)
    attrs = {'fileName': name, 'fileSize': len(data)}
    if kind == 'appPreviews':
        attrs['mimeType'] = 'video/mp4'
    made = call('POST', f'/v1/{kind}', {'data': {'type': kind, 'attributes': attrs,
                'relationships': {set_kind[:-1]: {'data': {'type': set_kind, 'id': set_id}}}}})['data']
    for op in made['attributes']['uploadOperations']:
        put(op, data[op['offset']:op['offset'] + op['length']])
    call('PATCH', f'/v1/{kind}/{made["id"]}', {'data': {'type': kind, 'id': made['id'],
         'attributes': {'uploaded': True, 'sourceFileChecksum': hashlib.md5(data).hexdigest()}}})
    print('  uploaded', name, len(data), 'bytes ->', made['id'])
    return made['id']


def replace(kind, set_kind, type_key, lid, wanted, list_key):
    """Each display type's set holds exactly the files given, in that order."""
    sets = call('GET', f'/v1/appStoreVersionLocalizations/{lid}/{set_kind}?include={kind}&limit=50')
    by_type = {s['attributes'][type_key]: s for s in sets['data']}
    for display, files in wanted.items():
        s = by_type.get(display)
        if s is None:
            s = call('POST', f'/v1/{set_kind}', {'data': {'type': set_kind, 'attributes': {type_key: display},
                     'relationships': {'appStoreVersionLocalization': {'data': {'type': 'appStoreVersionLocalizations', 'id': lid}}}}})['data']
            print('made set', display, s['id'])
        else:
            for old in (s.get('relationships', {}).get(kind, {}).get('data') or []):
                call('DELETE', f'/v1/{kind}/{old["id"]}')
                print('  removed old', old['id'])
        ids = [upload(kind, set_kind, s['id'], f) for f in files]
        call('PATCH', f'/v1/{set_kind}/{s["id"]}/relationships/{kind}', {'data': [{'type': kind, 'id': i} for i in ids]})
        print('set', display, 'now', len(ids), list_key)


def state(lid):
    for kind, set_kind, type_key in (('appScreenshots', 'appScreenshotSets', 'screenshotDisplayType'),
                                     ('appPreviews', 'appPreviewSets', 'previewType')):
        sets = call('GET', f'/v1/appStoreVersionLocalizations/{lid}/{set_kind}?include={kind}&limit=50')
        for s in sets['data']:
            items = s.get('relationships', {}).get(kind, {}).get('data') or []
            print(set_kind, s['attributes'][type_key], len(items))
        for inc in sets.get('included', []):
            a = inc['attributes']
            print('   ', a.get('fileName'), a.get('assetDeliveryState', {}).get('state'), a.get('fileSize'))


def fields():
    """metadata.md's fields by heading, "## Subtitle (30)" giving Subtitle and its limit of 30."""
    out, name = {}, None
    for line in open(os.path.join(ROOT, 'metadata.md')).read().split('\n'):
        if line.startswith('## '):
            title, _, limit = line[3:].partition(' (')
            name = title.strip()
            out[name] = {'limit': int(''.join(c for c in limit if c.isdigit()) or 0), 'lines': []}
        elif name:
            out[name]['lines'].append(line)
    for f in out.values():
        f['text'] = '\n'.join(f.pop('lines')).strip()
    return out


def text(vid, lid):
    """The version's promotional text, description and keywords, and the app's subtitle, as metadata.md has them.
    Each is checked against its limit first, so nothing goes up cut short."""
    f = fields()
    for name in ('Subtitle', 'Promotional Text', 'Description', 'Keywords'):
        if len(f[name]['text']) > f[name]['limit']:
            sys.exit(f'{name} is {len(f[name]["text"])} characters, over its {f[name]["limit"]}')
    call('PATCH', f'/v1/appStoreVersionLocalizations/{lid}', {'data': {'type': 'appStoreVersionLocalizations', 'id': lid,
         'attributes': {'promotionalText': f['Promotional Text']['text'], 'description': f['Description']['text'],
                        'keywords': f['Keywords']['text']}}})
    print('version text set:', ', '.join(f'{n} {len(f[n]["text"])}' for n in ('Promotional Text', 'Description', 'Keywords')))
    # The subtitle is the app's, not the version's: on the app info that is still being edited.
    infos = call('GET', f'/v1/apps/{APP}/appInfos')['data']
    info = next(i for i in infos if i['attributes'].get('appStoreState') != 'READY_FOR_SALE')
    locs = call('GET', f'/v1/appInfos/{info["id"]}/appInfoLocalizations')['data']
    loc = next((l for l in locs if l['attributes']['locale'] == 'en-US'), locs[0])
    call('PATCH', f'/v1/appInfoLocalizations/{loc["id"]}', {'data': {'type': 'appInfoLocalizations', 'id': loc['id'],
         'attributes': {'subtitle': f['Subtitle']['text']}}})
    print('subtitle set:', f['Subtitle']['text'])


def build(number, vid):
    for _ in range(60):
        data = call('GET', f'/v1/builds?filter[app]={APP}&filter[version]={number}&sort=-uploadedDate&limit=1')['data']
        if data and data[0]['attributes']['processingState'] == 'VALID':
            b = data[0]
            call('PATCH', f'/v1/appStoreVersions/{vid}/relationships/build', {'data': {'type': 'builds', 'id': b['id']}})
            print('version now has build', number, b['id'])
            return
        print('build', number, data[0]['attributes']['processingState'] if data else 'not there yet')
        time.sleep(60)
    sys.exit('build never became VALID')


if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'state'
    vid = version()
    lid = localization(vid)
    if what == 'state':
        state(lid)
    elif what == 'text':
        text(vid, lid)
    elif what == 'screenshots':
        wanted = {display: sorted(os.path.join(ROOT, folder, f) for f in os.listdir(os.path.join(ROOT, folder)) if f.endswith('.png'))
                  for display, folder in SETS.items()}
        for display, files in wanted.items():
            print(display, [os.path.basename(f) for f in files])
        replace('appScreenshots', 'appScreenshotSets', 'screenshotDisplayType', lid, wanted, 'screenshots')
    elif what == 'previews':
        wanted = {display: [os.path.join(ROOT, path)] for display, path in PREVIEWS.items()}
        replace('appPreviews', 'appPreviewSets', 'previewType', lid, wanted, 'previews')
    elif what == 'build':
        build(sys.argv[2], vid)
