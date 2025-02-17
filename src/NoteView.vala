/*
* Copyright (c) 2017 Lains
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 2 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*/

using Gtk;
using Gdk;

public class CompletionProvider : SourceCompletionProvider, Object {

  private MainWindow                      _win;
  private string                          _name;
  private GLib.List<SourceCompletionItem> _proposals;
  private SourceBuffer                    _buffer;

  /* Constructor */
  public CompletionProvider( MainWindow win, SourceBuffer buffer, string name, GLib.List<SourceCompletionItem> proposals ) {
    _win       = win;
    _buffer    = buffer;
    _name      = name;
    _proposals = new GLib.List<SourceCompletionItem>();
    foreach( SourceCompletionItem item in proposals ) {
      _proposals.append( item );
    }
  }

  public override string get_name() {
    return( _name );
  }

  private bool find_start_iter( out TextIter iter ) {

    TextIter cursor, limit;
    _buffer.get_iter_at_offset( out cursor, _buffer.cursor_position );

    limit = cursor.copy();
    limit.backward_word_start();
    limit.backward_char();

    iter = cursor.copy();
    return( iter.backward_find_char( (c) => { return( c == '\\' ); }, limit ) );

  }

  public override bool match( Gtk.SourceCompletionContext ctx ) {
    Gtk.TextIter iter;
    if( find_start_iter( out iter ) && _win.settings.get_boolean( "enable-unicode-input" ) ) {
      return( true );
    }
    return( false );
  }

  public override void populate( SourceCompletionContext context ) {
    TextIter start, end;
    if( find_start_iter( out start ) ) {
      _buffer.get_iter_at_offset( out end, _buffer.cursor_position );
      var text = _buffer.get_text( start, end, false );
      var proposals = new GLib.List<SourceCompletionItem>();
      foreach( SourceCompletionItem item in _proposals ) {
        if( item.get_label().has_prefix( text ) ) {
          proposals.append( item );
        }
      }
	    context.add_proposals( this, proposals, true );
    }
  }

  public override bool get_start_iter( SourceCompletionContext ctx, SourceCompletionProposal proposal, out TextIter iter ) {
    return( find_start_iter( out iter ) );
  }

  public bool activate_proposal( Gtk.SourceCompletionProposal proposal, Gtk.TextIter iter ) {
    return( false );
  }

  public Gtk.SourceCompletionActivation get_activation () {
    return( Gtk.SourceCompletionActivation.INTERACTIVE | Gtk.SourceCompletionActivation.USER_REQUESTED );
  }

}

/*
 This class is a slightly modified version of Lains Quilter SourceView.vala
 file.  The above header was kept in tact to indicate this.
*/
public class NoteView : Gtk.SourceView {

  private class UrlPos {
    public string url;
    public int    start;
    public int    end;
    public UrlPos( string u, int s, int e ) {
      url   = u;
      start = s;
      end   = e;
    }
  }

  private static bool   _path_init = false;
  private int           _last_lnum = -1;
  private string?       _last_url  = null;
  private Array<UrlPos> _last_urls;
  private int           _last_x;
  private int           _last_y;
  private Regex?        _url_re;
  public  SourceStyle   _srcstyle  = null;
  public  SourceBuffer  _buffer;

  public string text {
    set {
      buffer.text = value;
    }
    owned get {
      return( buffer.text );
    }
  }

  public bool modified {
    set {
      buffer.set_modified( value );
      clear();
    }
    get {
      return( buffer.get_modified() );
    }
  }

  /* Default constructor */
  public NoteView() {

    var sourceview_path = GLib.Path.build_filename( Environment.get_user_data_dir(), "minder", "gtksourceview-4" );
    var lang_path       = GLib.Path.build_filename( sourceview_path, "language-specs" );
    var style_path      = GLib.Path.build_filename( sourceview_path, "styles" );

    string[] lang_paths = {};

    get_style_context().add_class( "textfield" );

    var manager = Gtk.SourceLanguageManager.get_default();
    if( !_path_init ) {
      lang_paths = manager.get_search_path();
      lang_paths += lang_path;
      manager.set_search_path( lang_paths );
    }

    var style_manager = Gtk.SourceStyleSchemeManager.get_default();
    if( !_path_init ) {
      style_manager.prepend_search_path( style_path );
    }

    _path_init = true;

    var language = manager.get_language( get_default_language() );
    var style    = style_manager.get_scheme( get_default_scheme() );

    _buffer = new Gtk.SourceBuffer.with_language( language );
    _buffer.highlight_syntax = true;
    _buffer.set_max_undo_levels( 20 );
    _buffer.set_style_scheme( style );
    set_buffer( _buffer );

    modified = false;

    _buffer.changed.connect (() => {
      modified = true;
    });
    this.focus_in_event.connect( on_focus );
    this.motion_notify_event.connect( on_motion );
    this.button_press_event.connect( on_press );
    this.key_press_event.connect( on_keypress );
    this.key_release_event.connect( on_keyrelease );

    expand      = true;
    has_focus   = true;
    auto_indent = true;
    set_wrap_mode( Gtk.WrapMode.WORD );
    set_tab_width( 4 );
    set_insert_spaces_instead_of_tabs( true );

    try {
      _url_re = new Regex( Utils.url_re() );
    } catch( RegexError e ) {
      _url_re = null;
    }

    _last_urls = new Array<UrlPos>();

  }

  /* Returns the Markdown language parser used to highlight the text */
  private string get_default_language() {
    return( "markdown-minder" );
  }

  /* Returns the coloring scheme to use to highlight the text */
  private string get_default_scheme () {
    //return( "cobalt" );
    return( "minder" );
  }

  /* Clears the URL handler code to force it reparse the current line for URLs */
  private void clear() {
    _last_lnum = -1;
    _last_url  = null;
  }

  /* Returns the string of text for the current line */
  private string current_line( TextIter cursor ) {
    var start = cursor;
    var end   = cursor;
    start.set_line( start.get_line() );
    end.forward_line();
    return( start.get_text( end ).chomp() );
  }

  /*
   Parses all of the URLs in the given line and stores their positions within
   the _last_match_pos private member array.
  */
  private void parse_line_for_urls( string line ) {
    if( _url_re == null ) return;
    MatchInfo match_info;
    var       start = 0;
    _last_urls.remove_range( 0, _last_urls.length );
    try {
      while( _url_re.match_all_full( line, -1, start, 0, out match_info ) ) {
        int s, e;
        match_info.fetch_pos( 0, out s, out e );
        _last_urls.append_val( new UrlPos( line.substring( s, (e - s) ), s, e ) );
        start = e;
      }
    } catch( RegexError e ) {}
  }

  /* Returns true if the specified cursor is within a parsed URL pattern */
  private bool cursor_in_url( TextIter cursor ) {
    var offset = cursor.get_line_offset();
    for( int i=0; i<_last_urls.length; i++ ) {
      var link = _last_urls.index( i );
      if( (link.start <= offset) && (offset < link.end) ) {
        _last_url = link.url;
        return( true );
      }
    }
    _last_url = null;
    return( false );
  }

  /* Called when URL checking should be performed on the current line (if necessary) */
  private void enable_url_checking( int x, int y ) {
    TextIter cursor;
    var      win = get_window( TextWindowType.TEXT );
    get_iter_at_location( out cursor, x, y );
    if( _last_lnum != cursor.get_line() ) {
      parse_line_for_urls( current_line( cursor ) );
      _last_lnum = cursor.get_line();
    }
    if( cursor_in_url( cursor ) ) {
      win.set_cursor( new Cursor.for_display( get_display(), CursorType.HAND2 ) );
    } else {
      win.set_cursor( null );
    }
  }

  /* Called when URL checking should no longer be performed on the current line */
  private void disable_url_checking() {
    var win = get_window( TextWindowType.TEXT );
    win.set_cursor( null );
    _last_lnum = -1;
  }

  /* Adds the unicoder text completion service */
  public void add_unicode_completion( MainWindow win, UnicodeInsert unicoder ) {
    var provider = new CompletionProvider( win, _buffer, "Unicode", unicoder.create_proposals() );
    completion.add_provider( provider );
  }

  /*
   If the cursor is moved in the text viewer when the control key is held down,
   check to see if the cursor is over a URL.
  */
  private bool on_motion( EventMotion e ) {
    _last_x = (int)e.x;
    _last_y = (int)e.y;
    if( (bool)(e.state & ModifierType.CONTROL_MASK) ) {
      var int_x = (int)e.x;
      var int_y = (int)e.y;
      enable_url_checking( int_x, int_y );
      return( true );
    }
    disable_url_checking();
    return( false );
  }

  /*
   Called when the user clicks with the mouse.  If the cursor is over a URL,
   open the URL in an external application.
  */
  private bool on_press( EventButton e ) {
    if( (bool)(e.state & ModifierType.CONTROL_MASK) ) {
      var int_x = (int)e.x;
      var int_y = (int)e.y;
      enable_url_checking( int_x, int_y );
      if( _last_url != null ) {
        Utils.open_url( _last_url );
      }
      return( true );
    }
    return( false );
  }

  private bool on_keypress( EventKey e ) {
    if( e.keyval == 65507 ) {
      enable_url_checking( _last_x, _last_y );
    }
    return( false );
  }

  private bool on_keyrelease( EventKey e ) {
    if( e.keyval == 65507 ) {
      disable_url_checking();
    }
    return( false );
  }

  /* Clears the stored URL information */
  private bool on_focus( EventFocus e ) {
    clear();
    return( false );
  }

}
