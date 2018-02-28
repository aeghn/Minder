using Gtk;
using Cairo;

public enum NodeMode {
  NONE = 0,
  SELECTED,
  EDITABLE,
  EDITED
}

public struct NodeBounds {
  double x;
  double y;
  double width;
  double height;
}

public class Node : Object {

  /* Member variables */
  private   Node[] _children = {};
  protected double _width = 0;
  protected double _height = 0;
  private   int    _cursor = 0;   /* Location of the cursor when editing */

  /* Properties */
  public string   name   { get; set; default = ""; }
  public double   posx   { get; set; default = 50.0; }
  public double   posy   { get; set; default = 50.0; }
  public string   note   { get; set; default = ""; }
  public double   task   { get; set; default = -1.0; }
  public NodeMode mode   { get; set; default = NodeMode.NONE; }
  public Node     parent { get; protected set; default = null; }

  /* Default constructor */
  public Node() {}

  /* Constructor initializing string */
  public Node.with_name( string n ) {
    name = n;
  }

  /* Returns true if the node does not have a parent */
  public bool is_root() {
    return( parent == null );
  }

  /*
   Returns true if this node is a "main branch" which is a node attached
   directly to the parent.
  */
  public bool main_branch() {
    return( (parent != null) && (parent.parent == null) );
  }

  /* Returns true if the node is a leaf node */
  public bool is_leaf() {
    return( (parent != null) && (_children.length == 0) );
  }

  /* Returns true if the given cursor coordinates lies within this node */
  public virtual bool is_within( double x, double y ) {
    return( (x >= posx) && (x < (posx + _width)) && (y >= (posy - _height)) && (y < posy) );
  }

  /* Finds the node which contains the given pixel coordinates */
  public virtual Node? contains( double x, double y ) {
    if( is_within( x, y ) ) {
      return( this );
    } else {
      foreach (Node n in _children) {
        Node tmp = n.contains( x, y );
        if( tmp != null ) {
          return( tmp );
        }
      }
      return( null );
    }
  }

  /* Returns true if this node contains the given node */
  public virtual bool contains_node( Node node ) {
    if( node == this ) {
      return( true );
    } else {
      foreach (Node n in _children) {
        if( n.contains_node( node ) ) {
          return( true );
        }
      }
      return( false );
    }
  }

  /* Loads the file contents into this instance */
  public virtual bool load( DataInputStream stream ) {
    return( false );
  }

  /* Saves the current node */
  public virtual bool save( DataOutputStream stream, string prefix = "" ) {
    return( save_node( stream, prefix, "", "" ) );
  }

  /* Saves the node contents to the given data output stream */
  public bool save_node( DataOutputStream stream, string prefix = "", string attr = "", string nodes = "" ) {

    try {
      stream.put_string( prefix );
      stream.put_string( "  <node posx=\"" );
      stream.put_string( posx.to_string() );
      stream.put_string( "\" posy=\"" );
      stream.put_string( posy.to_string() );
      stream.put_string( "\" width=\"" );
      stream.put_string( _width.to_string() );
      stream.put_string( "\" height=\"" );
      stream.put_string( _height.to_string() );
      if( task >= 0 ) {
        stream.put_string( "\" task=\"" );
        stream.put_string( task.to_string() );
        stream.put_string( "\"" );
      }
      stream.put_string( attr );
      stream.put_string( ">\n" );

      stream.put_string( prefix );
      stream.put_string( "    <nodename>\n" );
      stream.put_string( name );
      stream.put_string( prefix );
      stream.put_string( "    </nodename>\n" );

      stream.put_string( prefix );
      stream.put_string( "    <nodenote>\n" );
      stream.put_string( note );
      stream.put_string( prefix );
      stream.put_string( "    </nodenote>\n" );

      stream.put_string( nodes );

      stream.put_string( prefix );
      stream.put_string( "    <nodes>\n" );
      foreach (Node n in _children) {
        n.save( stream, (prefix + "    ") );
      }
      stream.put_string( prefix );
      stream.put_string( "    </nodes>\n" );

      stream.put_string( prefix );
      stream.put_string( "  </node>\n" );
    } catch( Error e ) {
      return( false );
    }

    return( true );

  }

  /* Move the cursor in the given direction */
  public void move_cursor( int dir ) {
    _cursor += dir;
    if( _cursor < 0 ) {
      _cursor = 0;
    } else if( _cursor > name.length ) {
      _cursor = name.length;
    }
    mode = NodeMode.EDITED;
  }

  /* Moves the cursor to the beginning of the name */
  public void move_cursor_to_start() {
    _cursor = 0;
    mode = NodeMode.EDITED;
  }

  /* Moves the cursor to the end of the name */
  public void move_cursor_to_end() {
    _cursor = name.length;
    mode = NodeMode.EDITED;
  }

  /* Handles a backspace key event */
  public void edit_backspace() {
    if( _cursor > 0 ) {
      if( mode == NodeMode.EDITABLE ) {
        name    = "";
        _cursor = 0;
      } else {
        name = name.splice( (_cursor - 1), _cursor );
        _cursor--;
      }
    }
    mode = NodeMode.EDITED;
  }

  /* Handles a delete key event */
  public void edit_delete() {
    if( _cursor < name.length ) {
      name = name.splice( _cursor, (_cursor + 1) );
    } else if( mode == NodeMode.EDITABLE ) {
      name    = "";
      _cursor = 0;
    }
    mode = NodeMode.EDITED;
  }

  /* Inserts the given string at the current cursor position and adjusts cursor */
  public void edit_insert( string s ) {
    if( mode == NodeMode.EDITABLE ) {
      name    = s;
      _cursor = 1;
    } else {
      name = name.splice( _cursor, _cursor, s );
      _cursor += s.length;
    }
    mode = NodeMode.EDITED;
  }

  /* Detaches this node from its parent node */
  public virtual void detach() {
    if( parent != null ) {
      Node[] tmp = {};
      foreach (Node n in parent._children) {
        if( n != this ) {
          tmp += n;
        }
      }
      parent._children = tmp;
      parent = null;
    }
  }

  /* Removes this node from the node tree along with all descendents */
  public virtual void delete() {
    detach();
    _children = {};
  }

  /* Attaches this node as a child of the given node */
  public virtual void attach( Node parent ) {
    this.parent = parent;
    this.parent._children += this;
  }

  /* Returns a reference to the first child of this node */
  public virtual Node? first_child() {
    if( _children.length > 0 ) {
      return( _children[0] );
    }
    return( null );
  }

  /* Returns a reference to the last child of this node */
  public virtual Node? last_child() {
    if( _children.length > 0 ) {
      return( _children[_children.length-1] );
    }
    return( null );
  }

  /* Returns a reference to the next child after the specified child of this node */
  public virtual Node? next_child( Node n ) {
    int i = 0;
    foreach (Node c in _children) {
      if( c == n ) {
        if( (i + 1) < _children.length ) {
          return( _children[i+1] );
        } else {
          return( null );
        }
      }
      i++;
    }
    return( null );
  }

  /* Returns a reference to the next child after the specified child of this node */
  public virtual Node? prev_child( Node n ) {
    int i = 0;
    foreach (Node c in _children) {
      if( c == n ) {
        if( i > 0 ) {
          return( _children[i-1] );
        } else {
          return( null );
        }
      }
      i++;
    }
    return( null );
  }

  /* Calculates the boundaries of the given string */
  private void text_extents( Context ctx, string s, out TextExtents extents ) {
    if( s == "" ) {
      ctx.text_extents( "I", out extents );
      extents.width = 0;
    } else {
      string txt     = s;
      string chomped = s.chomp();
      int    diff    = txt.length - chomped.length;
      if( diff > 0 ) {
        txt = chomped + "i".ndup( diff );
      }
      ctx.text_extents( txt, out extents );
    }
  }

  /* Returns the extents of the given node name */
  protected void name_extents( Context ctx, out TextExtents extents ) {
    ctx.set_font_size( 14 );
    text_extents( ctx, name, out extents );
  }

  /* Adjusts the posx and posy values */
  public virtual void pan( double origin_x, double origin_y ) {
    posx -= origin_x;
    posy -= origin_y;
    foreach (Node n in _children) {
      n.pan( origin_x, origin_y );
    }
  }

  /* Returns the link point for this node */
  protected virtual void link_point( out double x, out double y ) {
    x = posx;
    y = posy;
  }

  /* Draws the node font to the screen */
  public virtual void draw_name( Context ctx ) {

    TextExtents name_extents;
    double      hmargin = 3;
    double      vmargin = 5;

    ctx.set_font_size( 14 );
    text_extents( ctx, name, out name_extents );

    _width  = name_extents.width;
    _height = name_extents.height;

    /* Draw the selection box around the text if the node is in the 'selected' state */
    if( (mode == NodeMode.SELECTED) || (mode == NodeMode.EDITABLE) ) {
      if( mode == NodeMode.SELECTED ) {
        ctx.set_source_rgba( 0.5, 0.5, 1, 1 );
      } else {
        ctx.set_source_rgba( 0, 0, 1, 1 );
      }
      ctx.rectangle( (posx - hmargin), ((posy - vmargin) - name_extents.height), (name_extents.width + (hmargin * 2)), (name_extents.height + (vmargin * 2)) );
      ctx.fill();
    }

    /* Output the text */
    ctx.move_to( posx, posy );
    ctx.set_source_rgba( 1, 1, 1, 1 );
    ctx.show_text( name );

    /* Draw the insertion cursor if we are in the 'editable' state */
    if( (mode == NodeMode.EDITABLE) || (mode == NodeMode.EDITED) ) {
      TextExtents extents;
      text_extents( ctx, name.substring( 0, _cursor ), out extents );
      ctx.set_source_rgba( 0, 1, 0, 1 );
      ctx.rectangle( (posx + 1 + extents.width), ((posy - vmargin) - name_extents.height), 1, (name_extents.height + (vmargin * 2)) );
      ctx.fill();
    }

  }

  /* Draws the node on the screen */
  public virtual void draw( Context ctx ) {}

  /* Draw this node and all child nodes */
  public void draw_all( Context ctx ) {
    draw( ctx );
    foreach (Node n in _children) {
      n.draw_all( ctx );
    }
  }

}
