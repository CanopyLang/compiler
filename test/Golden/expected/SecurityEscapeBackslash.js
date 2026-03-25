var $author$project$Main$withBackslash ='path\\to\\file';
var $author$project$Main$withNewlines ='line1\nline2\nline3';
var $author$project$Main$withTabs ='col1\tcol2\tcol3';
var $author$project$Main$main = $canopy$html$Html$text( _Utils_ap( $author$project$Main$withNewlines, _Utils_ap( $author$project$Main$withTabs, $author$project$Main$withBackslash)));
_Platform_export({'Main':{'init': _VirtualDom_init( $author$project$Main$main)(0)(0)}});scope['Canopy'] = scope['Elm'];
