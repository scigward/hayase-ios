// Source contracts plus executable bridge-stat tests, not a Swift/UIKit build.
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const folder = join(root, 'Hayase/Source/Components/UI/TorrentClient');
const read = name => readFileSync(join(folder, name), 'utf8');
const controller = read('DownloadsViewController.swift');
const button = readFileSync(join(root, 'Hayase/Source/Components/UI/Settings/SettingsSupportButton.swift'), 'utf8');
assert(button.includes('style.cornerStyle = .fixed'));
assert(button.includes('style.background.cornerRadius = 6'));
assert(controller.includes('progressStatsGrid?.setColumns(medium ? 4 : 2)'));
assert(controller.includes('protocolColumnsStack?.setColumns(wide ? 3 : (medium ? 2 : 1))'));
assert(controller.includes('rootViewController?.view.bounds.width'));
assert.equal((controller.match(/installScrollableTable\(/g) || []).length, 3);
assert(controller.includes('if let library { webLibraryEntries = library }'));
assert(controller.includes('if let files {'));
assert(!controller.includes('if !library.isEmpty { webLibraryEntries = library }'));
assert(controller.includes('webSnapshotGeneration == generationAtRequest'));
assert(controller.includes('selectedHex == selectionAtRequest'));
assert(controller.includes('singleTitleResult(id: mediaID)'));
assert(controller.includes('allVisibleLibraryRowsSelected'));
assert(controller.includes('showLibraryActionError(error)'));
assert(read('ColumnHeader.swift').includes('UIAction(title: "Asc"'));
assert(read('ColumnHeader.swift').includes('UIAction(title: "Desc"'));
assert(read('FileEntryTableCell.swift').includes('progressStack.widthAnchor.constraint(equalToConstant: 128)'));
assert(read('LibraryColumnCell.swift').includes('torrentNameLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 288)'));

for (const name of readdirSync(folder).filter(name => name.endsWith('.swift'))) {
  const source = read(name).replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*|"""[\s\S]*?"""|"(?:\\.|[^"\\])*"/g, '');
  const stack = [];
  const close = { ')': '(', ']': '[', '}': '{' };
  for (const char of source) {
    if ('([{'.includes(char)) stack.push(char);
    else if (close[char]) assert.equal(stack.pop(), close[char], `Delimiter mismatch: ${name}`);
  }
  assert.equal(stack.length, 0, `Unclosed delimiter: ${name}`);
}

const bridge = readFileSync(join(root, 'Hayase/Resources/WebTorrentBackend/webtorrent-bridge.js'), 'utf8');
const statsSource = bridge.slice(bridge.indexOf('function statsFromTorrent ('), bridge.indexOf('function refreshTorrentStatus ('));
const stats = vm.runInNewContext(`(${statsSource})`, {
  Date: { now: () => 125000 },
  torrentWires: torrent => torrent.wires || [],
  numericValue: value => Number.isFinite(Number(value)) ? Number(value) : 0,
});
const sample = { infoHash: 'test', length: 100, downloaded: 99.9, __hayaseStartedAt: 100000,
  timeRemaining: 1000, wires: [{ isSeeder: true }, { isSeeder: false }] };
assert.equal(stats(sample).time.elapsed, 25, 'elapsed must be seconds');
assert.equal(stats(sample).time.remaining, 1000, 'remaining must stay milliseconds');
assert.equal(stats(sample).progress, 0.9990000000000001);
assert.equal(stats({ ...sample, downloaded: 100 }).progress, 1);
assert.equal(stats({ ...sample, __hayaseStartedAt: undefined }).time.elapsed, 0);
assert.equal(stats({ ...sample, __hayaseStartedAt: 200000 }).time.elapsed, 0);
assert.equal(stats(sample).peers.seeders, 1);
assert.equal(stats(sample).peers.leechers, 1);
assert.throws(() => stats(null), /Torrent not found/);
console.log('Torrent client source contracts, delimiters, and bridge-stat tests passed.');
console.log('Not Swift compilation, an iOS build, or UIKit runtime validation.');
