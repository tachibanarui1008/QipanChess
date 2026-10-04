// Generate adapted SVGs and transparent PNG assets from the attributed badge palette.
// Usage: NODE_PATH=/path/to/node_modules node Scripts/build-move-badges.cjs
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const symbols = {
  brilliant: '<path d="M28 24h12l-2 34h-8z M52 24h12l-2 34h-8z" fill="white"/><circle cx="34" cy="72" r="6" fill="white"/><circle cx="58" cy="72" r="6" fill="white"/>',
  great: '<path d="M43 23h14l-2 37H45z" fill="white"/><circle cx="50" cy="74" r="7" fill="white"/>',
  best: '<path d="m50 19 9.1 19.5 21.4 2.7-15.7 14.9 4.1 21.2L50 66.6 31.1 77.3l4.1-21.2L19.5 41.2l21.4-2.7z" fill="white"/>',
  excellent: '<path d="M23 43h12v34H23z M41 44l10-19c2-4 7-4 9-1 3 5 1 12-2 17h13c7 0 10 4 8 10l-6 20c-1 4-4 6-8 6H41z" fill="white"/>',
  good: '<path d="m27 51 16 16 30-35" fill="none" stroke="white" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>',
  book: '<path d="M50 31c-10-8-22-9-33-5v43c13-3 24-1 33 6 9-7 20-9 33-6V26c-11-4-23-3-33 5Z" fill="white"/><path d="M50 32v39 M25 36c7-1 13 1 18 4 M25 47c7-1 13 1 18 4 M58 40c5-3 11-5 17-4 M58 51c5-3 11-5 17-4" fill="none" stroke="COLOR" stroke-width="4" stroke-linecap="round"/>',
  inaccuracy: '<text x="50" y="72" fill="white" font-family="Arial" font-weight="bold" font-size="60" text-anchor="middle">?!</text>',
  mistake: '<text x="50" y="74" fill="white" font-family="Arial" font-weight="bold" font-size="69" text-anchor="middle">?</text>',
  miss: '<path d="m31 31 38 38 M69 31 31 69" fill="none" stroke="white" stroke-width="10" stroke-linecap="round"/>',
  blunder: '<text x="50" y="73" fill="white" font-family="Arial" font-weight="bold" font-size="60" text-anchor="middle">??</text>',
};
(async () => {
  for (const [name, symbol] of Object.entries(symbols)) {
    const original = fs.readFileSync(path.join(root, 'ThirdParty/MoveBadges/upstream', `${name}.svg`), 'utf8');
    const color = original.match(/<circle[^>]*fill="(#[a-fA-F0-9]+)"/)[1];
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100"><circle cx="50" cy="50" r="49" fill="${color}"/>${symbol.replaceAll('COLOR', color)}</svg>\n`;
    fs.writeFileSync(path.join(root, 'Resources/MoveBadges', `${name}.svg`), svg);
    const asset = path.join(root, 'QipanChessApp/App/Assets.xcassets', `MoveBadge-${name}.imageset`);
    fs.mkdirSync(asset, { recursive: true });
    const images = [];
    for (let scale = 1; scale <= 3; scale++) {
      const filename = `${name}@${scale}x.png`;
      await sharp(Buffer.from(svg)).resize(96 * scale, 96 * scale).png().toFile(path.join(asset, filename));
      images.push({ filename, idiom: 'universal', scale: `${scale}x` });
    }
    fs.writeFileSync(path.join(asset, 'Contents.json'), JSON.stringify({ images, info: { author: 'xcode', version: 1 } }, null, 2) + '\n');
  }
})();
