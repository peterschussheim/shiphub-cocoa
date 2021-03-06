import DiffRow from './diff-row.js'

import h from 'util/make-element.js'

class TrailerRow extends DiffRow {
  constructor(mode, colorblind) {
    super();
    
    var gutterLeft = h('td', { className:'gutter gutter-left' });
    var gutterRight = h('td', { className:'gutter gutter-right' });
    
    var row;
    
    if (mode === 'unified') {
      var blank = h('td', {style:{height:'100%'}});
      if (colorblind) {
        var cbCol = h('td', { className:'cb cb-empty' });
        row = h('tr', {style:{height:'100%', backgroundColor: 'white'}}, gutterLeft, gutterRight, cbCol, blank);
      } else {
        row = h('tr', {style:{height:'100%', backgroundColor: 'white'}}, gutterLeft, gutterRight, blank);
      }
    } else {
      var left = h('td', {style:{height:'100%'}});
      var right = h('td', {style:{height:'100%'}});
      if (colorblind) {
        var cbCol1 = h('td', { className:'cb cb-empty' });
        var cbCol2 = h('td', { className:'cb cb-empty' });
        row = h('tr', {style:{height:'100%', backgroundColor: 'white'}}, gutterLeft, cbCol1, left, gutterRight, cbCol2, right);
      } else {
        row = h('tr', {style:{height:'100%', backgroundColor: 'white'}}, gutterLeft, left, gutterRight, right);
      }
    }
    this.node = row;
  }
  updateHighlight() { }
}

export default TrailerRow;
