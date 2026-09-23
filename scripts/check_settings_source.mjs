// Source-contract regression checks. These are not Swift compilation or UIKit tests.
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = path => readFileSync(join(root, 'Hayase/Source', path), 'utf8');
const shell = read('Routes/App/Settings/SettingsLayoutView.swift');
const controller = read('Routes/App/Settings/SettingsViewController.swift');
const rows = read('Routes/App/Settings/SettingsViewController+Content.swift');
const actions = read('Routes/App/Settings/SettingsViewController+Actions.swift');
const transition = read('Components/UI/Sidebar/HayaseRouteTransition.swift');
const sidebar = read('Components/UI/Sidebar/HayaseSidebarController.swift');
const extensions = read('Routes/App/Settings/SettingsExtensionsView.swift');
const typography = read('Components/UI/Settings/SettingsCardView.swift');
const toggle = read('Components/UI/Switch/HayaseSwitch.swift');
const routeIndex = read('Components/UI/Sidebar/HayaseTabIndex.swift');
const clientLayout = read('Components/UI/TorrentClient/DownloadsViewController.swift');
const episodePagination = read('Routes/App/Anime/[id]/EpisodesList.swift').split('final class PaginationBarView: UIView {')[1].split('// MARK: - Episode fetching')[0];
assert(clientLayout.includes('label.setContentHuggingPriority(.required, for: .vertical)'));
assert(clientLayout.includes('tabBarHeightConstraint?.isActive = medium && !wide'));
assert(!clientLayout.includes('medium ? 44 : 260'));
assert(!episodePagination.includes('pageStack.isHidden = isCompact'));
assert(episodePagination.includes('effectivePaginationWidth < 480'));
assert(episodePagination.includes('smallButtons ? 25.6 : 36'));
assert(episodePagination.includes('addSubview(compactInfoLabel)'));
assert(episodePagination.includes('compactInfoLabel.topAnchor.constraint(equalTo: controlsStack.bottomAnchor, constant: 20)'));

assert(!/UITableView|tableHeaderView|UITableViewDataSource/.test(controller + shell));
assert(shell.includes('let headingTop = safeAreaInsets.top + padding'));
assert(shell.includes('y: headingTop, width: headingWidth, height: 32'));
assert(shell.includes('subtitleLabel.frame.maxY + margin'));
assert(shell.includes('window?.rootViewController?.view.bounds.width'));
assert(shell.includes('let padding: CGFloat = medium ? 40 : 12'));
assert(shell.includes('viewport >= 768') && shell.includes('viewport >= 1024'));
assert(shell.includes('page.systemLayoutSizeFitting('));
assert(shell.includes('navigation.isHidden = !medium && !isIndex'));
assert(controller.includes('guard self.settingsRoute != route else { return }'));
assert(rows.includes('ComboBox(frame: .zero)') && actions.includes('CommandPopoverViewController('));
assert(rows.includes('case .extensions:') && rows.includes('SettingsExtensionsView(parent: self)'));
assert(!rows.includes('SettingsLicenseViewController'));
assert(!transition.includes('UIView.transition('));
assert(transition.includes('UIView.performWithoutAnimation'));
assert(transition.indexOf('changes()') < transition.indexOf('animation.addAnimations'));
assert(transition.includes('duration: 0.25'));
assert(transition.includes('CGPoint(x: 0.25, y: 0.1)'));
assert(transition.includes('UIAccessibility.isReduceMotionEnabled'));
assert(sidebar.includes('routeTransition.perform(in: view)'));
assert(sidebar.includes('routeTransition.finish()'));
assert(sidebar.includes('tabHost.setViewControllers([controller], animated: false)'));
assert(sidebar.includes('self.routeControllers[safe: targetIndex]'));
assert(!sidebar.includes('tabHost.selectedIndex = targetIndex'));
assert(!sidebar.includes('tabHost.observe('));
assert(routeIndex.includes('hayaseLogicalRouteIndex ?? navigationController?.hayaseLogicalRouteIndex'));
assert(toggle.includes('setContentHuggingPriority(.required, for: .horizontal)'));
assert(toggle.includes('setContentCompressionResistancePriority(.required, for: .horizontal)'));
assert(typography.includes('max(lineHeight, ceil(label.font.lineHeight))'));
assert(typography.includes('control.setContentHuggingPriority(.defaultHigh, for: .horizontal)'));
assert(extensions.indexOf('reload()') < extensions.indexOf('observer = NotificationCenter'));
assert(/queue: \.main\) \{ \[weak self\] _ in[\s\S]*?DispatchQueue\.main\.async \{ \[weak self\] in/.test(extensions));
assert(!existsSync(join(root, 'Hayase/Source/Routes/App/Settings/SettingsCells.swift')));
assert(!existsSync(join(root, 'Hayase/Source/Components/UI/Profile/AccountCardCell.swift')));
assert(read('Modules/Torrent/Backend/TorrentBackendSettings.swift').includes('let torrentSpeed: Double'));

// Catch extraction artifacts and mismatched delimiters without pretending to type-check.
function checkDelimiters(source, path) {
  const tokens = source.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*|"""[\s\S]*?"""|"(?:\\.|[^"\\])*"/g, '');
  const stack = [];
  const close = { ')': '(', ']': '[', '}': '{' };
  for (const char of tokens) {
    if ('([{'.includes(char)) stack.push(char);
    else if (close[char]) assert.equal(stack.pop(), close[char], `delimiter mismatch in ${path}`);
  }
  assert.equal(stack.length, 0, `unclosed delimiter in ${path}`);
  assert(!/\bfile(func|let|var)\b/.test(source), `invalid extraction modifier in ${path}`);
}
const folders = ['Routes/App/Settings', 'Components/UI/Settings', 'Components/UI/Switch'];
let count = 0;
for (const folder of folders) {
  for (const name of readdirSync(join(root, 'Hayase/Source', folder)).filter(name => name.endsWith('.swift'))) {
    const path = `${folder}/${name}`;
    checkDelimiters(read(path), path);
    count++;
  }
}
for (const name of ['AccountCardView.swift', 'AccountCardView+Authentication.swift', 'AccountCardView+Settings.swift']) {
  checkDelimiters(read(`Components/UI/Profile/${name}`), name);
  count++;
}
checkDelimiters(transition, 'HayaseRouteTransition.swift');
checkDelimiters(sidebar, 'HayaseSidebarController.swift');
checkDelimiters(routeIndex, 'HayaseTabIndex.swift');
checkDelimiters('class PaginationBarView {' + episodePagination, 'PaginationBarView');
console.log(`Layout source contracts passed; delimiter checks passed for ${count + 4} Swift files/components.`);
console.log('Not a Swift parse, type-check, build, or runtime test.');
