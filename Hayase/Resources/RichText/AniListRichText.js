/* Mirrors interface/Shadow.svelte. Uses locally bundled marked 18.0.6 + DOMPurify 3.4.12. */
(() => {
  const parser = new marked.Marked({ gfm: true, breaks: true, pedantic: false });
  const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  parser.use({ renderer: {
    link({ href, title, text }) {
      // Keep the final digit even when the AniList URL has no trailing slug.
      const anime = /^https:\/\/anilist\.co\/anime\/(\d+)(?:[/?#]|$)/.exec(href);
      const destination = anime ? '/#/app/anime/' + anime[1] : href;
      return '<a href="' + escape(destination) + '"' +
        (anime ? '' : ' target="_blank" rel="noopener noreferrer"') +
        (title ? ' title="' + escape(title) + '"' : '') + '>' + text + '</a>';
    }
  }});
  function render(input) {
    let html = String(input ?? '')
      .replace(/(http)(:([\/|.|\w|\s|-])*\.(?:jpg|.jpeg|gif|png|mp4|webm))/gi, '$1s$2')
      .replace(/img\s?(\d+%?)?\s?\((.[\S]+)\)/gi, "<img width='$1' src='$2'>")
      .replace(/(^|>| )@([A-Za-z0-9]+)/gm, "$1<a href='#' target='_blank' rel='noopener noreferrer'>@$2</a>")
      .replace(/youtube\s?\([^]*?([-_0-9A-Za-z]{10,15})[^]*?\)/gi, 'youtube ($1)')
      .replace(/webm\s?\(h?([A-Za-z0-9-._~:\/?#\[\]@!$&()*+,;=%]+)\)/gi, 'webmv(`$1`)')
      .replace(/~{3}([^]*?)~{3}/gm, '+++$1+++')
      .replace(/~!([^]*?)!~/gm, '<details><summary>Spoiler, click to view</summary>$1</details>');
    html = DOMPurify.sanitize(parser.parse(html, { async: false }), {
      ALLOWED_TAGS: ['a','b','blockquote','br','center','del','div','em','font','h1','h2','h3','h4','h5','hr','i','img','li','ol','p','pre','code','span','strike','strong','ul','details','summary'],
      ALLOWED_ATTR: ['align','height','href','src','target','width','rel']
    });
    html = html.replace(/\+{3}([^]*?)\+{3}/gm, '<center>$1</center>')
      .replace(/youtube\s?\(([-_0-9A-Za-z]{10,15})\)/gi, (_, id) =>
        '<iframe credentialless style="width:500px;height:200px;max-width:100%;border:none" title="youtube-embed" allow="autoplay" allowfullscreen src="https://www.youtube-nocookie.com/embed/' +
        id + '?enablejsapi=1&autoplay=0&controls=1&mute=0&disablekb=1&loop=1&playlist=' + id + '&cc_lang_pref=ja"></iframe>')
      .replace(/webmv\s?\(<code>([A-Za-z0-9-._~:\/?#\[\]@!$&()*+,;=%]+)<\/code>\)/gi, (_, rest) => {
        const url = 'h' + rest;
        return '<video playsinline muted loop controls><source src="' + escape(url) +
          '" type="video/webm">Your browser does not support the video tag.</video>';
      });
    // Media replacements run after the source sanitizer. Sanitize once more so
    // replacement syntax inside an attribute cannot create active attributes.
    return DOMPurify.sanitize(html, {
      ALLOWED_TAGS: ['a','b','blockquote','br','center','del','div','em','font','h1','h2','h3','h4','h5','hr','i','img','li','ol','p','pre','code','span','strike','strong','ul','details','summary','iframe','video','source'],
      ALLOWED_ATTR: ['align','height','href','src','target','width','rel','credentialless','style','title','allow','allowfullscreen','playsinline','muted','loop','controls','type']
    });
  }
  window.HayaseRichText = { render };
})();
