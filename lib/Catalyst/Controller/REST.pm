package Catalyst::Controller::REST;

=head1 NAME

Catalyst::Controller::REST - A RESTful controller 

=head1 SYNOPSIS

    package Foo::Controller::Bar;

    use base 'Catalyst::Controller::REST';

    sub thing : Local : ActionClass('REST') { }

    # Answer GET requests to "thing"
    sub thing_GET {
       my ( $self, $c ) = @_;
     
       # Return a 200 OK, with the data in entity
       # serialized in the body 
       $self->status_ok(
            $c, 
            entity => {
                some => 'data',
                foo  => 'is real bar-y',
            },
       );
    }

    # Answer PUT requests to "thing"
    sub thing_PUT { 
      .. some action ..
    }

=head1 DESCRIPTION

Catalyst::Controller::REST implements a mechanism for building
RESTful services in Catalyst.  It does this by extending the
normal Catalyst dispatch mechanism to allow for different 
subroutines to be called based on the HTTP Method requested, 
while also transparently handling all the serialization/deserialization for
you.

This is probably best served by an example.  In the above
controller, we have declared a Local Catalyst action on
"sub thing", and have used the ActionClass('REST').  

Below, we have declared "thing_GET" and "thing_PUT".  Any
GET requests to thing will be dispatched to "thing_GET", 
while any PUT requests will be dispatched to "thing_PUT".  

Any unimplemented HTTP methods will be met with a "405 Method Not Allowed"
response, automatically containing the proper list of available methods.  You
can override this behavior through implementing a custom
C<thing_not_implemented> method.  

If you do not provide an OPTIONS handler, we will respond to any OPTIONS
requests with a "200 OK", populating the Allowed header automatically.

Any data included in C<< $c->stash->{'rest'} >> will be serialized for you.
The serialization format will be selected based on the content-type
of the incoming request.  It is probably easier to use the L<STATUS HELPERS>,
which are described below.

The HTTP POST, PUT, and OPTIONS methods will all automatically deserialize the
contents of $c->request->body based on the requests content-type header.
A list of understood serialization formats is below.

If we do not have (or cannot run) a serializer for a given content-type, a 415
"Unsupported Media Type" error is generated. 

To make your Controller RESTful, simply have it

  use base 'Catalyst::Controller::REST'; 

=head1 SERIALIZATION

Catalyst::Controller::REST will automatically serialize your
responses, and deserialize any POST, PUT or OPTIONS requests. It evaluates
which serializer to use by mapping a content-type to a Serialization module.
We select the content-type based on: 

=over 2

=item B<The Content-Type Header>

If the incoming HTTP Request had a Content-Type header set, we will use it.

=item B<The content-type Query Parameter>

If this is a GET request, you can supply a content-type query parameter.

=item B<Evaluating the Accept Header>

Finally, if the client provided an Accept header, we will evaluate
it and use the best-ranked choice.  

=back

=head1 AVAILABLE SERIALIZERS

A given serialization mechanism is only available if you have the underlying
modules installed.  For example, you can't use XML::Simple if it's not already
installed.  

In addition, each serializer has it's quirks in terms of what sorts of data
structures it will properly handle.  L<Catalyst::Controller::REST> makes
no attempt to svae you from yourself in this regard. :) 

=over 2

=item C<text/x-yaml> => C<YAML::Syck>

Returns YAML generated by L<YAML::Syck>.

=item C<text/html> => C<YAML::HTML>

This uses L<YAML::Syck> and L<URI::Find> to generate YAML with all URLs turned
to hyperlinks.  Only useable for Serialization.

=item C<text/x-json> => C<JSON::Syck>

Uses L<JSON::Syck> to generate JSON output

=item C<text/x-data-dumper> => C<Data::Serializer>

Uses the L<Data::Serializer> module to generate L<Data::Dumper> output.

=item C<text/x-data-denter> => C<Data::Serializer>

Uses the L<Data::Serializer> module to generate L<Data::Denter> output.

=item C<text/x-data-taxi> => C<Data::Serializer>

Uses the L<Data::Serializer> module to generate L<Data::Taxi> output.

=item C<application/x-storable> => C<Data::Serializer>

Uses the L<Data::Serializer> module to generate L<Storable> output.

=item C<application/x-freezethaw> => C<Data::Serializer>

Uses the L<Data::Serializer> module to generate L<FreezeThaw> output.

=item C<text/x-config-general> => C<Data::Serializer>

Uses the L<Data::Serializer> module to generate L<Config::General> output.

=item C<text/x-php-serialization> => C<Data::Serializer>

Uses the L<Data::Serializer> module to generate L<PHP::Serialization> output.

=item C<text/xml> => C<XML::Simple>

Uses L<XML::Simple> to generate XML output.  This is probably not suitable
for any real heavy XML work. Due to L<XML::Simple>s requirement that the data
you serialize be a HASHREF, we transform outgoing data to be in the form of:

  { data => $yourdata }

=item L<View>

Uses a regular Catalyst view.  For example, if you wanted to have your 
C<text/html> and C<text/xml> views rendered by TT:

	'text/html' => [ 'View', 'TT' ],
	'text/xml'  => [ 'View', 'XML' ],
	
Will do the trick nicely. 

=back

By default, L<Catalyst::Controller::REST> will return a C<415 Unsupported Media Type>
response if an attempt to use an unsupported content-type is made.  You
can ensure that something is always returned by setting the C<default>
config option:

   __PACKAGE__->config->{'serialize'}->{'default'} = 'text/x-yaml';

Would make it always fall back to the serializer plugin defined for text/x-yaml.

Implementing new Serialization formats is easy!  Contributions
are most welcome!  See L<Catalyst::Action::Serialize> and
L<Catalyst::Action::Deserialize> for more information.

=head1 CUSTOM SERIALIZERS

If you would like to implement a custom serializer, you should create two new
modules in the L<Catalyst::Action::Serialize> and
L<Catalyst::Action::Deserialize> namespace.  Then assign your new class
to the content-type's you want, and you're done.

=head1 STATUS HELPERS

Since so much of REST is in using HTTP, we provide these Status Helpers.
Using them will ensure that you are responding with the proper codes,
headers, and entities.

These helpers try and conform to the HTTP 1.1 Specification.  You can
refer to it at: L<http://www.w3.org/Protocols/rfc2616/rfc2616.txt>.  
These routines are all implemented as regular subroutines, and as
such require you pass the current context ($c) as the first argument.

=over 4

=cut

use strict;
use warnings;
use base 'Catalyst::Controller';
use Params::Validate qw(:all);

__PACKAGE__->mk_accessors(qw(serialize));

__PACKAGE__->config(
    serialize => {
        'stash_key' => 'rest',
        'map'       => {
            'text/html'          => 'YAML::HTML',
            'text/xml'           => 'XML::Simple',
            'text/x-yaml'        => 'YAML',
            'text/x-json'        => 'JSON',
            'text/x-data-dumper' => [ 'Data::Serializer', 'Data::Dumper' ],
            'text/x-data-denter' => [ 'Data::Serializer', 'Data::Denter' ],
            'text/x-data-taxi'   => [ 'Data::Serializer', 'Data::Taxi'   ],
            'application/x-storable'    => [ 'Data::Serializer', 'Storable'     ],
            'application/x-freezethaw'  => [ 'Data::Serializer', 'FreezeThaw'   ],
            'text/x-config-general' => [ 'Data::Serializer', 'Config::General' ],
            'text/x-php-serialization' => [ 'Data::Serializer', 'PHP::Serialization' ],
        },
    }
);

sub begin : ActionClass('Deserialize') {
}

sub end : ActionClass('Serialize') {
}

=item status_ok

Returns a "200 OK" response.  Takes an "entity" to serialize.

Example:

  $self->status_ok(
    $c, 
    entity => {
        radiohead => "Is a good band!",
    }
  );

=cut

sub status_ok {
    my $self = shift;
    my $c    = shift;
    my %p    = validate( @_, { entity => 1, }, );

    $c->response->status(200);
    $self->_set_entity( $c, $p{'entity'} );
    return 1;
}

=item status_created

Returns a "201 CREATED" response.  Takes an "entity" to serialize,
and a "location" where the created object can be found.

Example:

  $self->status_created(
    $c, 
    location => $c->req->uri->as_string,
    entity => {
        radiohead => "Is a good band!",
    }
  );

In the above example, we use the requested URI as our location.
This is probably what you want for most PUT requests.

=cut

sub status_created {
    my $self = shift;
    my $c    = shift;
    my %p    = validate(
        @_,
        {
            location => { type     => SCALAR | OBJECT },
            entity   => { optional => 1 },
        },
    );

    my $location;
    if ( ref( $p{'location'} ) ) {
        $location = $p{'location'}->as_string;
    } else {
        $location = $p{'location'};
    }
    $c->response->status(201);
    $c->response->header( 'Location' => $location );
    $self->_set_entity( $c, $p{'entity'} );
    return 1;
}

=item status_accepted

Returns a "202 ACCEPTED" response.  Takes an "entity" to serialize.

Example:

  $self->status_accepted(
    $c, 
    entity => {
        status => "queued",
    }
  );

=cut

sub status_accepted {
    my $self = shift;
    my $c    = shift;
    my %p    = validate( @_, { entity => 1, }, );

    $c->response->status(202);
    $self->_set_entity( $c, $p{'entity'} );
    return 1;
}

=item status_bad_request

Returns a "400 BAD REQUEST" response.  Takes a "message" argument
as a scalar, which will become the value of "error" in the serialized
response.

Example:

  $self->status_bad_request(
    $c, 
    message => "Cannot do what you have asked!",
  );

=cut

sub status_bad_request {
    my $self = shift;
    my $c    = shift;
    my %p    = validate( @_, { message => { type => SCALAR }, }, );

    $c->response->status(400);
    $c->log->debug( "Status Bad Request: " . $p{'message'} );
    $self->_set_entity( $c, { error => $p{'message'} } );
    return 1;
}

=item status_not_found

Returns a "404 NOT FOUND" response.  Takes a "message" argument
as a scalar, which will become the value of "error" in the serialized
response.

Example:

  $self->status_not_found(
    $c, 
    message => "Cannot find what you were looking for!",
  );

=cut

sub status_not_found {
    my $self = shift;
    my $c    = shift;
    my %p    = validate( @_, { message => { type => SCALAR }, }, );

    $c->response->status(404);
    $c->log->debug( "Status Not Found: " . $p{'message'} );
    $self->_set_entity( $c, { error => $p{'message'} } );
    return 1;
}

sub _set_entity {
    my $self   = shift;
    my $c      = shift;
    my $entity = shift;
    if ( defined($entity) ) {
        $c->stash->{ $self->config->{'serialize'}->{'stash_key'} } = $entity;
    }
    return 1;
}

=back

=head1 MANUAL RESPONSES

If you want to construct your responses yourself, all you need to
do is put the object you want serialized in $c->stash->{'rest'}.

=head1 IMPLEMENTATION DETAILS

This Controller ties together L<Catalyst::Action::REST>,
L<Catalyst::Action::Serialize> and L<Catalyst::Action::Deserialize>.  It should be suitable for most applications.  You should be aware that it:

=over 4

=item Configures the Serialization Actions

This class provides a default configuration for Serialization.  It is currently:

  __PACKAGE__->config(
      serialize => {
         'stash_key' => 'rest',
         'map'       => {
            'text/html'          => 'YAML::HTML',
            'text/xml'           => 'XML::Simple',
            'text/x-yaml'        => 'YAML',
            'text/x-json'        => 'JSON',
            'text/x-data-dumper' => [ 'Data::Serializer', 'Data::Dumper' ],
            'text/x-data-denter' => [ 'Data::Serializer', 'Data::Denter' ],
            'text/x-data-taxi'   => [ 'Data::Serializer', 'Data::Taxi'   ],
            'application/x-storable'    => [ 'Data::Serializer', 'Storable'     
],
            'application/x-freezethaw'  => [ 'Data::Serializer', 'FreezeThaw'   
],
            'text/x-config-general' => [ 'Data::Serializer', 'Config::General' ]
,
            'text/x-php-serialization' => [ 'Data::Serializer', 'PHP::Serialization' ],
          },
      }
  );

You can read the full set of options for this configuration block in
L<Catalyst::Action::Serialize>.

=item Sets a C<begin> and C<end> method for you

The C<begin> method uses L<Catalyst::Action::Deserialize>.  The C<end>
method uses L<Catalyst::Action::Serialize>.  If you want to override
either behavior, simply implement your own C<begin> and C<end> actions
and use NEXT:

  my Foo::Controller::Monkey;
  use base qw(Catalyst::Controller::REST);

  sub begin :Private {
    my ($self, $c) = @_;
    ... do things before Deserializing ...
    $self->NEXT::begin($c); 
    ... do things after Deserializing ...
  } 

  sub end :Private {
    my ($self, $c) = @_;
    ... do things before Serializing ...
    $self->NEXT::end($c); 
    ... do things after Serializing ...
  }

=head1 A MILD WARNING

I have code in production using L<Catalyst::Controller::REST>.  That said,
it is still under development, and it's possible that things may change
between releases.  I promise to not break things unneccesarily. :)

=head1 SEE ALSO

L<Catalyst::Action::REST>, L<Catalyst::Action::Serialize>,
L<Catalyst::Action::Deserialize>

For help with REST in general:

The HTTP 1.1 Spec is required reading. http://www.w3.org/Protocols/rfc2616/rfc2616.txt

Wikipedia! http://en.wikipedia.org/wiki/Representational_State_Transfer

The REST Wiki: http://rest.blueoxen.net/cgi-bin/wiki.pl?FrontPage

=head1 AUTHOR

Adam Jacob <adam@stalecoffee.org>, with lots of help from mst and jrockway

Marchex, Inc. paid me while I developed this module.  (http://www.marchex.com)

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
