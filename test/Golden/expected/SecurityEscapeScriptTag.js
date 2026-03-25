var $author$project$Main$dangerous ='<script>alert(\'xss\')</script>';
var $author$project$Main$withQuotes ='She said \"hello\" & goodbye';
var $author$project$Main$main = $canopy$html$Html$text( _Utils_ap( $author$project$Main$dangerous, $author$project$Main$withQuotes));
_Platform_export({'Main':{'init': _VirtualDom_init( $author$project$Main$main)(0)(0)}});scope['Canopy'] = scope['Elm'];
