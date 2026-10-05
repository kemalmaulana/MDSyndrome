// Bridge between the app and the vendored libraries. Document content arrives only as function
// arguments (callAsyncJavaScript), never spliced into script text.
(function () {
  'use strict';

  const stage = () => document.getElementById('stage');
  const loading = {};
  let counter = 0;

  function load(path) {
    if (!loading[path]) {
      loading[path] = new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = path;
        script.onload = () => resolve();
        script.onerror = () => reject(new Error('Could not load ' + path));
        document.head.appendChild(script);
      });
    }
    return loading[path];
  }

  function size(element) {
    const box = element.getBoundingClientRect();
    return { width: Math.ceil(box.width), height: Math.ceil(box.height) };
  }

  // SVG with an explicit pixel size taken from its viewBox, so layout does not depend on the container.
  function pin(svg) {
    const viewBox = svg.viewBox && svg.viewBox.baseVal;
    if (viewBox && viewBox.width > 0 && viewBox.height > 0) {
      svg.setAttribute('width', viewBox.width);
      svg.setAttribute('height', viewBox.height);
    }
    svg.style.maxWidth = 'none';
    svg.style.display = 'block';
  }

  async function mermaidRender(source, options) {
    await load('mermaid.min.js');
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: options.dark ? 'dark' : 'default',
      fontFamily: options.fontFamily,
      flowchart: { useMaxWidth: false },
      sequence: { useMaxWidth: false },
      gantt: { useMaxWidth: false },
      er: { useMaxWidth: false },
      class: { useMaxWidth: false },
      state: { useMaxWidth: false },
      journey: { useMaxWidth: false },
      pie: { useMaxWidth: false }
    });
    await mermaid.parse(source);   // throws on a syntax error, without drawing an error diagram
    const result = await mermaid.render('mds' + (++counter), source);
    stage().innerHTML = result.svg;
    const svg = stage().querySelector('svg');
    pin(svg);
    return size(stage());
  }

  async function graphvizRender(source, options) {
    await load('viz-global.js');
    window.__viz = window.__viz || await Viz.instance();
    const attributes = options.dark
      ? { graph: { bgcolor: 'transparent', color: options.foreground, fontcolor: options.foreground },
          node: { color: options.foreground, fontcolor: options.foreground },
          edge: { color: options.foreground, fontcolor: options.foreground } }
      : { graph: { bgcolor: 'transparent' }, node: {}, edge: {} };
    const svg = window.__viz.renderSVGElement(source, {
      graphAttributes: attributes.graph, nodeAttributes: attributes.node, edgeAttributes: attributes.edge
    });
    stage().replaceChildren(svg);
    pin(svg);
    return size(stage());
  }

  async function katexRender(source, options) {
    await load('katex/katex.min.js');
    const html = katex.renderToString(source, {
      displayMode: !!options.display, throwOnError: true, trust: false, output: 'html', strict: 'ignore'
    });
    const root = stage();
    root.style.fontSize = options.fontSize + 'px';
    root.style.color = options.foreground;
    root.style.lineHeight = '0';
    // A zero-height inline-block sits on the baseline, which tells how far the formula hangs below it.
    root.innerHTML = '<span id="probe" style="display:inline-block;width:0;height:0;vertical-align:baseline"></span>' + html;
    await document.fonts.ready;
    root.getBoundingClientRect();
    await document.fonts.ready;
    const katexBox = root.querySelector('.katex').getBoundingClientRect();
    const probeBox = root.querySelector('#probe').getBoundingClientRect();
    const box = root.getBoundingClientRect();
    return { width: Math.ceil(box.width), height: Math.ceil(box.height), baseline: Math.max(0, box.bottom - probeBox.bottom), katexHeight: katexBox.height };
  }

  window.MDS = {
    render: function (kind, source, options) {
      stage().replaceChildren();
      stage().removeAttribute('style');
      if (kind === 'mermaid') return mermaidRender(source, options);
      if (kind === 'graphviz') return graphvizRender(source, options);
      if (kind === 'katex') return katexRender(source, options);
      return Promise.reject(new Error('Unknown renderer ' + kind));
    }
  };
})();
