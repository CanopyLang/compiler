var $author$project$Main$greeting = F2( function(first,last){ return ('Hello ' +( first +(' ' +( last +'!'))));});
var $author$project$Main$main = $canopy$html$Html$text( A2( $author$project$Main$greeting,'World','!'));
var $author$project$Main$plain ='just a string';
_Platform_export({'Main':{'init': _VirtualDom_init( $author$project$Main$main)(0)(0)}});scope['Canopy'] = scope['Elm'];
