"""Bounded, read-only Git commit metadata for the sandboxed app.

No executable, config, hooks, alternate object stores or network access. Follow
the first-parent history only. Metadata outside the selected project is ignored.
Pack/index formats: https://git-scm.com/docs/gitformat-pack
"""
import hashlib
from itertools import islice
import re
import struct
import zlib
from datetime import datetime, timedelta, timezone
from pathlib import Path

LIMIT = 1_000_000


class Repository:
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.git = self.path(self.root / '.git')
        if self.git.is_file():
            target = self.read(self.git, 4096).decode().strip()
            if not target.startswith('gitdir: '): raise ValueError('Invalid gitdir')
            self.git = self.path(self.root / target[8:])
        self.budget = 8_000_000
        self.cache = {}
        self.indexes = None

    def path(self, path):
        path = path.resolve()
        if not path.is_relative_to(self.root): raise ValueError('Git metadata outside selected project')
        return path

    def read(self, path, limit=LIMIT):
        with self.path(path).open('rb') as stream:
            data = stream.read(limit + 1)
        if len(data) > limit: raise ValueError('Git metadata too large')
        return data

    def head(self):
        head = self.read(self.git / 'HEAD', 4096).decode().strip()
        if head.startswith('ref: '):
            ref = head[5:]
            if not ref.startswith('refs/') or '..' in ref.split('/'): raise ValueError('Invalid ref')
            loose = self.path(self.git / ref)
            if loose.is_file(): return self.read(loose, 4096).decode().strip()
            for line in self.read(self.git / 'packed-refs').decode().splitlines():
                if line.endswith(' ' + ref): return line.split(' ', 1)[0]
            raise ValueError('Missing ref')
        return head

    def inflate(self, stream):
        decoder = zlib.decompressobj()
        result = bytearray()
        while not decoder.eof:
            chunk = stream.read(min(8192, self.budget))
            self.budget -= len(chunk)
            if not chunk: raise ValueError('Git read budget exceeded or truncated object')
            result.extend(decoder.decompress(chunk, LIMIT + 1 - len(result)))
            if len(result) > LIMIT: raise ValueError('Git object too large')
        return bytes(result)

    def offset(self, index, oid):
        with self.path(index).open('rb') as stream:
            if stream.read(8) != b'\xfftOc\x00\x00\x00\x02': return None
            def u32(position):
                stream.seek(position)
                return struct.unpack('>I', stream.read(4))[0]
            count = u32(8 + 255 * 4)
            if count > 20_000_000: raise ValueError('Git index too large')
            low = u32(8 + (oid[0] - 1) * 4) if oid[0] else 0
            high = u32(8 + oid[0] * 4)
            names = 8 + 1024
            while low < high:
                mid = (low + high) // 2
                stream.seek(names + mid * len(oid))
                found = stream.read(len(oid))
                if found < oid: low = mid + 1
                elif found > oid: high = mid
                else:
                    offset = u32(names + count * (len(oid) + 4) + mid * 4)
                    if offset & 0x80000000:
                        stream.seek(names + count * (len(oid) + 8) + (offset & 0x7fffffff) * 8)
                        offset = struct.unpack('>Q', stream.read(8))[0]
                    return offset
        return None

    def packed(self, pack, offset, hash_size, depth):
        if depth > 32: raise ValueError('Git delta depth exceeded')
        with self.path(pack).open('rb') as stream:
            header = stream.read(12)
            if header[:4] != b'PACK' or int.from_bytes(header[4:8], 'big') not in (2, 3):
                raise ValueError('Invalid pack')
            stream.seek(offset)
            def byte(): return stream.read(1)[0]
            current = byte(); kind = (current >> 4) & 7; size = current & 15; shift = 4
            while current & 128:
                if shift > 63: raise ValueError('Invalid object size')
                current = byte(); size |= (current & 127) << shift; shift += 7
            if size > LIMIT: raise ValueError('Git object too large')
            base_offset = base_oid = None
            if kind == 6:
                current = byte(); distance = current & 127
                for _ in range(10):
                    if not current & 128: break
                    current = byte(); distance = ((distance + 1) << 7) | (current & 127)
                else: raise ValueError('Invalid delta offset')
                base_offset = offset - distance
                if base_offset < 12 or base_offset >= offset: raise ValueError('Invalid delta offset')
            elif kind == 7:
                base_oid = stream.read(hash_size).hex()
            data = self.inflate(stream)
        if len(data) != size: raise ValueError('Git object size mismatch')
        if kind in (6, 7):
            base_kind, base = self.packed(pack, base_offset, hash_size, depth + 1) if kind == 6 else self.object(base_oid, depth + 1)
            return base_kind, apply_delta(base, data)
        if kind != 1: raise ValueError('Expected commit')
        return 'commit', data

    def object(self, oid, depth=0):
        if depth > 32 or not re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', oid): raise ValueError('Invalid object ID')
        if oid in self.cache: return self.cache[oid]
        loose = self.path(self.git / 'objects' / oid[:2] / oid[2:])
        if loose.is_file():
            with loose.open('rb') as stream: raw = self.inflate(stream)
            header, data = raw.split(b'\0', 1)
            kind, size = header.decode().split(' ')
            if kind != 'commit' or int(size) != len(data): raise ValueError('Expected commit')
        else:
            if self.indexes is None:
                directory = self.path(self.git / 'objects/pack')
                self.indexes = []
                if directory.is_dir():
                    for index in islice(directory.iterdir(), 128):
                        if index.suffix == '.idx': self.indexes.append(index)
                        if len(self.indexes) > 32: raise ValueError('Too many Git packs')
            for index in self.indexes:
                offset = self.offset(index, bytes.fromhex(oid))
                if offset is not None:
                    kind, data = self.packed(index.with_suffix('.pack'), offset, len(oid) // 2, depth)
                    break
            else: raise ValueError('Missing object')
        digest = hashlib.sha1 if len(oid) == 40 else hashlib.sha256
        if digest(b'commit ' + str(len(data)).encode() + b'\0' + data).hexdigest() != oid:
            raise ValueError('Git object checksum mismatch')
        self.cache[oid] = kind, data
        return kind, data


def apply_delta(base, delta):
    position = 0
    def byte():
        nonlocal position
        value = delta[position]; position += 1; return value
    def integer():
        result = 0
        for shift in range(0, 70, 7):
            value = byte(); result |= (value & 127) << shift
            if not value & 128: return result
        raise ValueError('Invalid delta integer')
    if integer() != len(base): raise ValueError('Delta base mismatch')
    size = integer()
    if size > LIMIT: raise ValueError('Delta too large')
    result = bytearray()
    while position < len(delta):
        command = byte()
        if command & 128:
            offset = sum(byte() << (8 * i) for i in range(4) if command & (1 << i))
            length = sum(byte() << (8 * i) for i in range(3) if command & (16 << i)) or 0x10000
            if offset + length > len(base): raise ValueError('Delta range exceeded')
            result.extend(base[offset:offset + length])
        elif command:
            if position + command > len(delta): raise ValueError('Truncated delta')
            result.extend(delta[position:position + command]); position += command
        else: raise ValueError('Invalid delta instruction')
        if len(result) > size: raise ValueError('Delta output exceeded')
    if len(result) != size: raise ValueError('Delta size mismatch')
    return bytes(result)


def read_activity(root):
    result = []
    try:
        repo = Repository(root); oid = repo.head()
        for _ in range(5):
            _, raw = repo.object(oid)
            headers, message = raw.split(b'\n\n', 1)
            date = re.search(rb'^author .* (\d+) ([+-])(\d\d)(\d\d)$', headers, re.M)
            if not date: break
            offset = timedelta(hours=int(date[3]), minutes=int(date[4])) * (-1 if date[2] == b'-' else 1)
            timestamp = datetime.fromtimestamp(int(date[1]), timezone(offset)).isoformat()
            encoding = re.search(rb'^encoding ([\w-]+)$', headers, re.M)
            title = message.decode(encoding[1].decode() if encoding else 'utf-8', errors='replace').strip().split('\n', 1)[0][:1000]
            result.append({'commit': oid[:7], 'date': timestamp, 'title': title})
            parent = re.search(rb'^parent ([0-9a-f]+)$', headers, re.M)
            if not parent: break
            oid = parent[1].decode()
    except (OSError, ValueError, IndexError, KeyError, LookupError, OverflowError, struct.error, zlib.error):
        pass  # Git is optional context, never a prerequisite for progress.
    return result
