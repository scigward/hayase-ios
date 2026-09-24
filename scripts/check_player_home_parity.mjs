// Source contracts and model tests only: not Swift compilation or UIKit rendering.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
const root = resolve(import.meta.dirname, '..');
const read = path => readFileSync(resolve(root, 'Hayase/Source', path), 'utf8');
const home = read('Routes/App/Home/BrowseAnimeViewController.swift');
const featured = home.split(/private final class FeaturedBannerCell:[^{]+\{/)[1].split('private final class SkeletonBannerCell')[0];
assert.equal((featured.match(/override func didMoveToWindow\(/g) ?? []).length, 1);
assert(featured.includes('self.artworkGeneration == generation'));
assert(featured.includes('self.items.map(\\.id) == nextItems.map(\\.id)'));
assert(featured.includes('widthAnchor.constraint(equalToConstant: 480)'));
assert(!featured.includes('clearlogoHeightMax'));
assert(featured.includes('FollowerAvatarStackView()'));
assert(featured.includes('fade.duration = 0.8'));
assert(!featured.includes('Timer.scheduledTimer'));
assert(featured.includes('func animationDidStop('));
assert(featured.includes('animation.value(forKey: "generation") as? Int == progressGeneration'));
assert(featured.includes('bannerBackdropClipView.isHidden = true'));
assert(home.includes('cell.configure(with: bannerResults, selectedID: self.selectedFeaturedID)'));
assert(home.includes('overlap: 8, cutoutBorder: 4'));
const search = read('Components/UI/Extensions/ExtensionSearchViewController.swift');
assert(!search.includes('pendingHud'));
assert(search.includes('if pendingPlayer == nil { cleanupPendingState() }'));
assert(search.includes('guard pendingVideoService === vs else { return }'));
assert(search.includes('dismissSearchForPlayback(completion: openPlayer)'));
assert(search.includes('0.3 - (CACurrentMediaTime() - began)'));
assert(search.includes('player.finishMetadataLoading()'));
const player = read('Components/UI/Player/VideoPlayerViewController.swift');
assert(player.includes('onCancelMetadataLoading?()'));
assert(player.includes('surface.addSubview(loading)'));
assert(read('Components/UI/Player/PlayerMetadataLoadingView.swift').includes('override func didMoveToWindow()'));
assert(read('Components/UI/Player/MiniPlayerManager.swift').includes('guard activePlayer?.isLoadingMetadata != true else { return }'));
const stripes = read('App/HayaseStripeLayer.swift');
assert(stripes.includes('angleDegrees: 40') && stripes.includes('period: 10'));
assert(stripes.includes('let periodStart = minProjection'));
assert(stripes.includes('if case .customBackground = pattern'));
assert(!stripes.includes('blurView.alpha ='));
assert(read('Components/UI/Player/PlayerMetadataLoadingView.swift').includes('Loading torrent metadata,\\nthis might take a minute...'));
const editor = read('Components/EntryEditorViewController.swift');
assert(editor.includes('SettingsDialogViewController'));
assert(editor.includes('lists: currentEntry?.customLists'));
assert(!editor.includes('UIPickerView'));
const form = read('Components/EntryEditorFormView.swift');
assert(form.includes('viewportWidth >= 640'));
assert(form.includes('equalToConstant: 260') && form.includes('equalToConstant: 400'));
for (const path of ['Routes/App/Chat/HayaseChatViewController.swift', 'Routes/App/W2G/W2GViewController.swift']) {
  const source = read(path);
  assert(source.includes('view.window?.rootViewController?.view.bounds.width ?? view.bounds.width) >= 768'));
  assert(source.includes('compactUsersHeight.constant = min('));
  assert(!source.includes('userListTableView.isHidden = true'));
}
const schedule = read('Routes/App/Schedule/ScheduleViewController.swift');
assert(schedule.includes('(firstWeekday + 5) % 7'));
assert(schedule.includes('(8 - lastWeekday) % 7'));
assert(schedule.includes('viewportWidth >= 1024 ? 192 : 96'));
assert(!schedule.includes('UIAlertController'));
assert(schedule.includes('onList: requestedFilter'));
// Exercise the Monday-first grid offsets for all weekday starts and month lengths.
for (let year = 2024; year <= 2030; year++) {
  for (let month = 0; month < 12; month++) {
    const first = new Date(Date.UTC(year, month, 1));
    const last = new Date(Date.UTC(year, month + 1, 0));
    const appleFirst = first.getUTCDay() + 1, appleLast = last.getUTCDay() + 1;
    const start = new Date(first); start.setUTCDate(1 - (appleFirst + 5) % 7);
    const end = new Date(last); end.setUTCDate(last.getUTCDate() + (8 - appleLast) % 7);
    assert.equal(start.getUTCDay(), 1); assert.equal(end.getUTCDay(), 0);
    assert.equal(((end - start) / 86400000 + 1) % 7, 0);
  }
}
const tracked = execFileSync('git', ['diff', '--name-only', 'HEAD'], { cwd: root, encoding: 'utf8' });
const added = execFileSync('git', ['ls-files', '--others', '--exclude-standard'], { cwd: root, encoding: 'utf8' });
const paths = [...new Set((tracked + '\n' + added).split(/\r?\n/).filter(p => p.endsWith('.swift')))];
for (const path of paths) {
  const source = readFileSync(resolve(root, path), 'utf8');
  const stripped = source.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*|"""[\s\S]*?"""|"(?:\\.|[^"\\])*"/g, '');
  const stack = [], closes = { ')': '(', ']': '[', '}': '{' };
  for (const char of stripped) {
    if ('([{'.includes(char)) stack.push(char);
    else if (closes[char]) assert.equal(stack.pop(), closes[char], path);
  }
  assert.equal(stack.length, 0, path);
}
console.log('Player/home/editor/chat/schedule contracts passed; 84 calendar month models passed.');
console.log('Delimiter checks passed for ' + paths.length + ' changed Swift files. Not an iOS build or runtime test.');
