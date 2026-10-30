import mermaid from 'mermaid';
window.configureTheme = theme => {
  const {dark, background, text, primary, secondary, accent, line} = theme;
  document.documentElement.style.backgroundColor = background;
  document.body.style.backgroundColor = background;
  document.body.style.color = text;
  mermaid.initialize({startOnLoad: false, securityLevel: 'strict', theme: 'base',
    fontFamily: '-apple-system, sans-serif', maxTextSize: 50000, maxEdges: 500,
    secure: ['secure', 'securityLevel', 'startOnLoad', 'maxTextSize', 'maxEdges', 'theme', 'themeCSS', 'themeVariables'],
    themeVariables: {darkMode: dark, background, textColor: text, titleColor: text,
      primaryColor: primary, primaryTextColor: text, primaryBorderColor: accent,
      secondaryColor: secondary, secondaryTextColor: text, secondaryBorderColor: line,
      tertiaryColor: secondary, tertiaryTextColor: text, tertiaryBorderColor: line,
      lineColor: line, mainBkg: primary, nodeTextColor: text,
      clusterBkg: secondary, clusterBorder: line, edgeLabelBackground: background,
      actorBkg: primary, actorTextColor: text, actorBorder: accent, actorLineColor: line,
      signalColor: text, signalTextColor: text, labelBoxBkgColor: secondary,
      labelBoxBorderColor: line, labelTextColor: text, loopTextColor: text,
      noteBkgColor: secondary, noteTextColor: text, noteBorderColor: accent,
      activationBkgColor: secondary, activationBorderColor: accent,
      pieTitleTextColor: text, pieSectionTextColor: text, pieLegendTextColor: text},
    flowchart: {htmlLabels: false}});
};
window.draw = async source => {
  const host = document.getElementById('diagram');
  host.replaceChildren();
  try {
    const {svg} = await mermaid.render('graph', source);
    host.innerHTML = svg;
    const image = host.querySelector('svg');
    image.style.maxWidth = 'none';
    image.style.backgroundColor = document.body.style.backgroundColor;
    const box = image.viewBox.baseVal;
    const scale = Math.min(1, 700 / box.width, 700 / box.height);
    image.setAttribute('width', Math.ceil(box.width * scale));
    image.setAttribute('height', Math.ceil(box.height * scale));
    return {width: Math.ceil(box.width * scale), height: Math.ceil(box.height * scale)};
  } catch (error) {
    host.replaceChildren();
    throw new Error(String(error));
  }
};
window.prepareVector = () => {
    const image = document.querySelector('#diagram svg');
    const box = image.viewBox.baseVal;
    const width = Math.ceil(box.width), height = Math.ceil(box.height);
    image.setAttribute('width', width);
    image.setAttribute('height', height);
    // Keep natural-size vector text and measure all visible label transforms.
    let fontSize = Infinity;
    const walker = document.createTreeWalker(image, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) {
      const node = walker.currentNode;
      const parent = node.parentElement;
      if (!node.textContent.trim() || !parent || parent.closest('style,defs,title,desc,script')) continue;
      const style = getComputedStyle(parent);
      if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity) === 0) continue;
      const svgParent = parent instanceof SVGGraphicsElement ? parent : parent.closest('foreignObject');
      const matrix = svgParent?.getScreenCTM();
      const size = parseFloat(style.fontSize) * (matrix ? Math.hypot(matrix.c, matrix.d) : 1);
      if (Number.isFinite(size) && size > 0 && parent.getBoundingClientRect().height > 0) fontSize = Math.min(fontSize, size);
    }
    return {width, height, fontSize: Number.isFinite(fontSize) ? fontSize : null};
};
