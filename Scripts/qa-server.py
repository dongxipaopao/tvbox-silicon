#!/usr/bin/env python3
"""Deterministic local API/playlists/media for manual app QA; binds only to loopback."""
import argparse
import json
import pathlib
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, default=8765)
parser.add_argument('--media', type=pathlib.Path, default=root/'build/player-test.mp4')
args = parser.parse_args()
base = f'http://127.0.0.1:{args.port}'
lock = threading.Lock()
counts = {}
reports = []

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *values):
        print(fmt % values, flush=True)

    def send(self, body, status=200, mime='application/json'):
        if isinstance(body, (dict, list)): body = json.dumps(body, ensure_ascii=False).encode()
        if isinstance(body, str): body = body.encode()
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        q = {k:v[0] for k,v in parse_qs(parsed.query).items()}
        with lock:
            counts[path] = counts.get(path, 0) + 1
            count = counts[path]
        if path == '/config.json':
            return self.send({'sites': [
                {'key':'qa-index','name':'片单推荐 / Discover','type':4,'api':base+'/index','indexs':1,'searchable':0},
                {'key':'qa-standard','name':'标准视频 / Movies','type':4,'api':base+'/api'},
                {'key':'qa-slow','name':'慢速加载 / Slow','type':4,'api':base+'/slow'},
                {'key':'qa-empty','name':'空结果 / Empty','type':4,'api':base+'/empty'},
                {'key':'qa-error','name':'失败重试 / Unavailable','type':4,'api':base+'/failure'},
                {'key':'qa-unsupported','name':'不支持的格式 / Unsupported','type':0,'api':base+'/unsupported'}
            ],'lives':[
                {'name':'测试频道 / Channels','url':base+'/live.m3u'},
                {'name':'空播放列表 / Empty','url':base+'/empty.m3u'},
                {'name':'不可用播放列表 / Unavailable','url':base+'/failure.m3u'}
            ]})
        # Python source: a real spider the embedded CPython must run (the name carries the interpreter's version).
        if path == '/py-config.json': return self.send({'sites': [{'key':'qa-py','name':'Python 源 / Python','type':3,'api':base+'/spider.py'}], 'lives': []})
        # Update-feed fixtures: the fork's own feed announces its own release; an empty one announces nothing.
        if path == '/qa-feed-empty.json': return self.send({'releases': []})
        if path == '/qa-feed-new.json': return self.send({'releases': [{'version':'9.9.9','build':999,'date':'2026-11-27','links':{'ios':base,'tvos':base},'features':[{'symbol':'checkmark.shield','title':{'en':'Fixture update','zh-Hans':'夹具更新测试'},'detail':{'en':'QA fixture release from the fork feed.','zh-Hans':'来自分叉自家更新源的质检夹具说明。'}}]}]})
        if path == '/spider.py':
            return self.send("""import sys
sys.path.append('..')
from base.spider import Spider
class Spider(Spider):
    def init(self, extend=''):
        pass
    def getName(self):
        return 'qa-py'
    def homeContent(self, filter):
        return {'class': [{'type_id': 'py', 'type_name': 'Python'}], 'list': []}
    def homeVideoContent(self):
        return {'list': []}
    def categoryContent(self, tid, pg, filter, extend):
        v = '.'.join(str(x) for x in sys.version_info[:3])
        return {'page': 1, 'pagecount': 1, 'list': [{'vod_id': 'py%d' % i, 'vod_name': 'Python %s 运行成功 %02d' % (v, i), 'vod_pic': '', 'vod_remarks': 'py'} for i in range(1, 7)]}
    def searchContent(self, key, quick, pg='1'):
        return {'list': [{'vod_id': 'pys', 'vod_name': key + ' Python搜索成功', 'vod_pic': '', 'vod_remarks': 'py'}]}
    def detailContent(self, ids):
        return {'list': [{'vod_id': ids[0], 'vod_name': 'Python 详情 ' + ids[0], 'vod_play_from': 'py', 'vod_play_url': '第1集$http://127.0.0.1/x'}]}
    def playerContent(self, flag, id, vipFlags):
        return {'parse': 0, 'url': id}
""",mime='text/x-python')
        # Remote double-click: two lines of three episodes; line one plays clip.mp4, line two slow.mp4. Each play is reported.
        if path == '/rc-config.json': return self.send({'sites': [{'key':'qa-rc','name':'遥控切换 / Remote','type':4,'api':base+'/rc'}], 'lives': []})
        if path == '/rc':
            if 'play' in q:
                reports.append('play ' + q['play'])
                return self.send({'parse':0,'url':base+('/slow.mp4' if q['play'].startswith('l2') else '/clip.mp4')+'?ep='+q['play']})
            if 'ids' in q and q['ids'] == 'rc2':
                return self.send({'list':[{'vod_id':'rc2','vod_name':'单集影片','vod_pic':base+'/poster.png','vod_play_from':'唯一线路','vod_play_url':'第1集$l1-1'}]})
            if 'ids' in q:
                return self.send({'list':[{'vod_id':q['ids'],'vod_name':'遥控测试影片','vod_pic':base+'/poster.png','vod_play_from':'线路甲$$$线路乙',
                    'vod_play_url':'#'.join(f'第{i}集$l1-{i}' for i in (1,2,3))+'$$$'+'#'.join(f'第{i}集$l2-{i}' for i in (1,2,3))}]})
            return self.send({'class':[{'type_id':'movies','type_name':'电影'}],'pagecount':1,'list':[{'vod_id':'rc1','vod_name':'遥控测试影片','vod_pic':base+'/poster.png'},{'vod_id':'rc2','vod_name':'单集影片','vod_pic':base+'/poster.png'}]})
        # Same-source line failover: line one's only episode points at a dead address, line two's plays.
        if path == '/fo-config.json': return self.send({'sites': [{'key':'qa-fo','name':'线路切换 / Lines','type':4,'api':base+'/fo'}], 'lives': []})
        # Line two has two entries of episode 1: the same episode can't be told for sure, so nothing may switch.
        if path == '/fo2-config.json': return self.send({'sites': [{'key':'qa-fo2','name':'线路不明 / Ambiguous','type':4,'api':base+'/fo2'}], 'lives': []})
        if path == '/fo2':
            if 'play' in q: return self.send({'parse':0,'url':base+('/missing.mp4' if q['play'] == 'dead-1' else '/clip.mp4?ambiguous=1')})
            if 'ids' in q:
                return self.send({'list':[{'vod_id':q['ids'],'vod_name':'线路不明影片','vod_pic':base+'/poster.png',
                    'vod_play_from':'坏线路$$$两个第一集','vod_play_url':'第1集$dead-1$$$第1集$episode-1#第1集$episode-2'}]})
            return self.send({'class':[{'type_id':'movies','type_name':'电影'}],'pagecount':1,'list':[{'vod_id':'fo2','vod_name':'线路不明影片','vod_pic':base+'/poster.png'}]})
        if path == '/fo':
            if 'play' in q: return self.send({'parse':0,'url':base+('/missing.mp4' if q['play'] == 'dead-1' else '/clip.mp4')})
            if 'ids' in q:
                return self.send({'list':[{'vod_id':q['ids'],'vod_name':'线路测试影片','vod_pic':base+'/poster.png',
                    'vod_play_from':'坏线路$$$好线路','vod_play_url':'第1集$dead-1$$$第1集$episode-1'}]})
            return self.send({'class':[{'type_id':'movies','type_name':'电影'}],'pagecount':1,'list':[{'vod_id':'fo1','vod_name':'线路测试影片','vod_pic':base+'/poster.png'}]})
        # A Listenify-style music extension: one chart shelf, a search that echoes its text, and a song that plays the QA clip.
        if path == '/qa-report':
            reports.append(q.get('text',''))
            return self.send({'ok':1})
        if path == '/reports': return self.send(reports)
        if path == '/music-ext.js':
            return self.send("""/*!
 * @name QA Fake FM
 * @description QA fixture extension
 * @version v1
 * @author qa
 */
const appConfig = { ver: 1, name: 'qafm', tabLibrary: { name: '探索', groups: [
  { name: '测试榜单', type: 'playlist', ui: 1, ext: { gid: 'charts' } } ] } }
function song(id, name) { return { id: 's' + id, name: name, duration: 20, artist: { id: 'a', name: 'QA Singer' }, ext: { songmid: 'm' + id } } }
async function getConfig() { return jsonify(appConfig) }
async function getPlaylists(ext) {
  const { gid } = argsify(ext)
  if (gid !== 'charts') return jsonify({ list: [] })
  return jsonify({ list: [{ id: 'c1', name: 'Chart One', artist: { name: 'qa' }, ext: { gid: 'chart-songs' } }] })
}
async function getAlbums(ext) { return jsonify({ list: [] }) }
async function getArtists(ext) { return jsonify({ list: [] }) }
async function getSongs(ext) {
  const { gid, page } = argsify(ext)
  if (gid === 'chart-songs' && (!page || page <= 1)) return jsonify({ list: [song(1, 'Chart Song One')] })
  return jsonify({ list: [] })
}
async function search(ext) {
  const { text, type } = argsify(ext)
  if (type === 'song') return jsonify({ list: [song(7, text + ' hit')] })
  return jsonify({ list: [] })
}
async function getSongInfo(ext) { return jsonify({ urls: ['BASE/clip.mp4'] }) }
""".replace('BASE', base), mime='application/javascript')
        if path == '/empty-config.json': return self.send({'sites': [], 'lives': [{'name':'测试频道','url':base+'/live.m3u'}]})
        # A source whose video details never arrive, for Back while a page is still loading.
        # Also one whose details fail, and one whose video has no episodes, for Back once the page has given up.
        if path == '/stall-config.json': return self.send({'sites': [{'key':'qa-stall','name':'详情卡住 / Stalled','type':4,'api':base+'/stall'},
            {'key':'qa-broken','name':'详情失败 / Broken','type':4,'api':base+'/stall?broken=1'},
            {'key':'qa-no-episodes','name':'没有剧集 / No episodes','type':4,'api':base+'/stall?episodes=0'},
            {'key':'qa-stream-stall','name':'播放卡住 / Stalled stream','type':4,'api':base+'/api?stream=stall'}], 'lives': []})
        if path == '/stall':
            if 'ids' in q and q.get('broken') == '1': return self.send('Service unavailable',503,'text/plain')
            if 'ids' in q and q.get('episodes') == '0': return self.send({'list': [{'vod_id':q['ids'],'vod_name':'测试影片 '+q['ids']}]})
            if 'ids' in q or 'play' in q: time.sleep(120); return self.send({'list': []})
            return self.send({'class':[{'type_id':'movies','type_name':'电影'}],'pagecount':1,
                'list':[{'vod_id':str(i),'vod_name':f'测试影片 {i:02d}','vod_pic':base+'/poster.png','vod_remarks':'更新至 36 集'} for i in range(1,13)]})
        # Downloads: episodes 1 and 2 arrive at once, the rest trickle in, so finished and running downloads show together.
        if path == '/downloads-config.json': return self.send({'sites': [{'key':'qa-downloads','name':'下载 / Downloads','type':4,'api':base+'/api?stream=download'}], 'lives': []})
        # A live stream that never answers, for Back while the player is still loading.
        if path == '/stall.m3u8': time.sleep(120); return self.send('Not found',404,'text/plain')
        if path == '/invalid.json': return self.send('{invalid JSON')
        if path == '/empty.m3u': return self.send('#EXTM3U', mime='audio/x-mpegurl')
        if path == '/failure.m3u': return self.send('Unavailable',503,'text/plain')
        if path == '/live.m3u':
            lines=['#EXTM3U']
            for i in range(1,19):
                group=['新闻','电影','Sports'][i%3]
                lines += [f'#EXTINF:-1 tvg-logo="{base}/poster.png" group-title="{group}",测试频道 {i:02d}',f'{base}/clip.mp4?channel={i}']
            lines += ['#EXTINF:-1 group-title="故障测试",无法播放的频道',base+'/missing.mp4']
            return self.send('\n'.join(lines),mime='audio/x-mpegurl')
        if path == '/poster.png':
            return self.send((root/'Design/yingxia-icon.png').read_bytes(),mime='image/png')
        if path == '/frozen.mp4':
            # The headers and the moov box arrive, then the media data never does: AVPlayer goes readyToPlay and
            # waits for a buffer that never fills, so the player's no-picture timeout can be seen for real.
            media = args.media
            if not media.exists(): return self.send('Generate clip with Scripts/test-player.sh first',404,'text/plain')
            size = media.stat().st_size
            self.send_response(200)
            self.send_header('Content-Type','video/mp4'); self.send_header('Accept-Ranges','bytes')
            self.send_header('Content-Length',str(size))
            self.end_headers()
            try:
                with media.open('rb') as stream:
                    self.wfile.write(stream.read(65536)); self.wfile.flush()
                time.sleep(600)
            except (BrokenPipeError,ConnectionResetError): pass
            return
        if path in ['/clip.mp4','/slow.mp4','/portrait.mp4','/tone.mp4']:
            media = args.media if path in ['/clip.mp4','/slow.mp4'] else args.media.with_name(path.lstrip('/'))
            if not media.exists(): return self.send('Generate clip with Scripts/test-player.sh first',404,'text/plain')
            size=media.stat().st_size
            match=re.match(r'bytes=(\d+)-(\d*)',self.headers.get('Range',''))
            start=int(match[1]) if match else 0
            end=min(int(match[2]) if match and match[2] else size-1,size-1)
            if start>=size:
                self.send_response(416);self.send_header('Content-Range',f'bytes */{size}');self.end_headers();return
            self.send_response(206 if match else 200)
            self.send_header('Content-Type','video/mp4');self.send_header('Accept-Ranges','bytes')
            self.send_header('Content-Length',str(end-start+1))
            if match:self.send_header('Content-Range',f'bytes {start}-{end}/{size}')
            self.end_headers()
            with media.open('rb') as stream:
                stream.seek(start)
                body=stream.read(end-start+1)
                try:
                    if path!='/slow.mp4':self.wfile.write(body)
                    # About 16 KB/s: minutes for the clip.
                    else:
                        for offset in range(0,len(body),4096):self.wfile.write(body[offset:offset+4096]);self.wfile.flush();time.sleep(0.25)
                except (BrokenPipeError,ConnectionResetError):pass
            return
        if path == '/missing.mp4': return self.send('Not found',404,'text/plain')
        if path == '/api/v2/search/anime':
            return self.send({'animes':[{'bangumiId':90001,'animeTitle':'测试影片 1','typeDescription':'QA fixture'}]})
        if path == '/api/v2/bangumi/90001':
            return self.send({'bangumi':{'episodes':[{'episodeId':900010001,'episodeTitle':'第1话'},
                                                   {'episodeId':900010002,'episodeTitle':'第2话'}]}})
        if path == '/api/v2/comment/900010001':
            return self.send({'comments':[{'p':f'{time},1,16777215,qa','m':'Automatic match QA fixture'} for time in [1,30,90]]})
        if path == '/api/v2/comment/900010002':
            return self.send({'comments':[{'p':f'{time},1,16777215,qa','m':'Next episode QA fixture'} for time in [2,20,80]]})
        if path == '/counts': return self.send(counts)
        if path == '/failure': return self.send('Service unavailable',503,'text/plain')
        if path in ['/api','/slow','/empty','/index']:
            if path=='/slow':time.sleep(2)
            categories=[{'type_id':'movies','type_name':'电影'},{'type_id':'series','type_name':'电视剧'},{'type_id':'empty','type_name':'空分类'}]
            # qa-stream-stall: episodes whose stream never answers, so the player opens with episode buttons and no picture.
            if 'play' in q:
                if q['play'] == 'qa-portrait': return self.send({'parse':0,'url':base+'/portrait.mp4'})
                if q['play'] == 'episode-frozen': return self.send({'parse':0,'url':base+'/frozen.mp4'})
                if q['play'] == 'episode-tone': return self.send({'parse':0,'url':base+'/tone.mp4'})
                if q.get('stream')=='download':return self.send({'parse':0,'url':base+('/clip.mp4' if q['play'] in ['episode-1','episode-2'] else '/slow.mp4')})
                return self.send({'parse':0,'url':base+('/stall.m3u8' if q.get('stream')=='stall' else '/clip.mp4')})
            if q.get('ids') == 'qa-playerfix':
                return self.send({'list':[{'vod_id':'qa-playerfix','vod_name':'Player fixtures','vod_pic':base+'/poster.png',
                    'vod_play_from':'Main','vod_play_url':'Frozen$episode-frozen#Tone$episode-tone'}]})
            if q.get('ids', '').startswith('qa-cache-ui-'):
                return self.send({'list':[{'vod_id':q['ids'],'vod_name':'Cached episode fixture',
                    'vod_play_from':'Main','vod_play_url':'Wide$episode-1#Portrait$qa-portrait#Third$episode-3#Fourth$episode-4'}]})
            if q.get('ids')=='drive':
                return self.send({'list':[{'vod_id':'drive','vod_name':'玩具总动员 5','vod_pic':base+'/poster.png','vod_remarks':'4K HDR',
                    'vod_content':'这是一段用于检查详情页布局的简介。 '*24,
                    'vod_play_from':'夸父原1$$$夸父智1$$$嘟嘟无限2','vod_play_url':'$$$'.join(f'[18.35GB] 玩-居-宗 01.mkv$file-{i}' for i in range(3))}]})
            if 'ids' in q:
                return self.send({'list':[{'vod_id':q['ids'],'vod_name':'测试影片 '+q['ids'],'vod_pic':base+'/poster.png',
                    'vod_content':'这是一段用于检查详情页布局的简介。 '*24,
                    'vod_play_from':'线路一$$$线路二','vod_play_url':'#'.join(f'第 {i} 集$episode-{i}' for i in range(1,37))+'$$$备用$alternate'}]})
            if path=='/empty' or q.get('t')=='empty' or q.get('wd') in ['没有这个','notfound']:
                return self.send({'class':categories,'list':[],'pagecount':1})
            pg=int(q.get('pg','1'))
            title=q.get('wd') or ('剧集' if q.get('t')=='series' else '测试影片')
            # Searching "few" finds two videos per source and one page: Global Search's results fit in one row.
            few=q.get('wd','').startswith('few')
            if q.get('wd') == 'qa-playerfix':
                return self.send({'class':categories,'list':[{'vod_id':'qa-playerfix','vod_name':'Player fixtures','vod_pic':base+'/poster.png'}],'pagecount':1})
            if q.get('wd') == 'Breaking Bad':
                # Exact-title fixtures, with the quality notes real sources put after a title.
                return self.send({'list':[{'vod_id':'bb%d'%i,'vod_name':n,'vod_pic':base+'/poster.png','vod_remarks':r} for i,(n,r) in enumerate([('Breaking Bad【4K】','4K HDR'),('Breaking Bad','1080P'),('Breaking Bad [国语]','HD'),('Breaking Bad','更新至 62 集')])]})
            videos=[{'vod_id':str((pg-1)*12+i),'vod_name':f'{title} {i:02d}', 'vod_pic':base+'/poster.png','vod_remarks':'更新至 36 集' if i%2 else '1080P'} for i in range(1,3 if few else 13)]
            if path=='/index':
                videos=[{'vod_name':'测试影片','vod_pic':base+'/poster.png','vod_remarks':'7.8'},{'vod_name':'剧集','vod_pic':base+'/poster.png'}]
            # 电影 has TVBox filters (地区, 年份, 排序), for the category filter chips.
            option=lambda names:[{'n':n,'v':'' if n=='全部' else n} for n in names]
            filters={'movies':[{'key':'area','name':'地区','value':option(['全部','中国大陆','中国香港','中国台湾','美国','日本','韩国','泰国','印度','其他'])},
                {'key':'year','name':'年份','value':option(['全部']+[str(y) for y in range(2026,1999,-1)]+['更早'])},
                {'key':'by','name':'排序','value':[{'n':'最新','v':'time'},{'n':'最热','v':'hits'},{'n':'评分','v':'score'}]}]}
            return self.send({'class':categories,'filters':filters,'list':videos,'pagecount':3 if path!='/index' and not few else 1})
        return self.send('Not found',404,'text/plain')

print(f'QA subscription: {base}/config.json',flush=True)
ThreadingHTTPServer(('127.0.0.1',args.port),Handler).serve_forever()
