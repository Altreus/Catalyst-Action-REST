package Catalyst::Action::Deserialize::JSON::XS;

use Moose;
use namespace::autoclean;
BEGIN {
    $ENV{'PERL_JSON_BACKEND'} = 2; # Always use compiled JSON::XS
}

extends 'Catalyst::Action::Deserialize::JSON';
use JSON::XS ();

our $VERSION = '1.16'; # VERSION

__PACKAGE__->meta->make_immutable;

1;
