(function () {
  'use strict';
  function capture(rawURL, source) {
    try {
      var url = new URL(rawURL, location.href);
      if (url.hostname !== 'amp-api.music.apple.com') return;
      var headers = new Headers(source || {});
      var picked = {};
      ['authorization', 'media-user-token', 'x-apple-client-version'].forEach(function (key) {
        var value = headers.get(key);
        if (value) picked[key] = value;
      });
      if (Object.keys(picked).length) {
        window.webkit.messageHandlers.beatAuth.postMessage({url: url.href, headers: picked});
      }
    } catch (_) {}
  }

  var originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = function (input, init) {
      var url = typeof input === 'string' ? input : input && input.url;
      var headers = init && init.headers;
      if (!headers && input && input.headers) headers = input.headers;
      capture(url, headers);
      return originalFetch.apply(this, arguments);
    };
  }

  var originalOpen = XMLHttpRequest.prototype.open;
  var originalSetHeader = XMLHttpRequest.prototype.setRequestHeader;
  var originalSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__beatURL = url;
    this.__beatHeaders = {};
    return originalOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
    if (this.__beatHeaders) this.__beatHeaders[name] = value;
    return originalSetHeader.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function () {
    capture(this.__beatURL, this.__beatHeaders);
    return originalSend.apply(this, arguments);
  };
})();
