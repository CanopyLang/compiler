var $author$project$Main$dangerous ='<script>alert(\'xss\')</script>';
var $author$project$Main$main = $canopy$html$Html$text( $author$project$Main$dangerous);
var $author$project$Main$withQuotes ='She said \"hello\" & goodbye';
_Platform_export({'Main':{'init': _VirtualDom_init( $author$project$Main$main)(0)(0)}});scope['Canopy'] = scope['Elm'];
