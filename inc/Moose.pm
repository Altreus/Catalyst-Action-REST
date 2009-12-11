#line 1
package Moose;
use strict;
use warnings;

use 5.008;

our $VERSION   = '0.93';
$VERSION = eval $VERSION;
our $AUTHORITY = 'cpan:STEVAN';

use Scalar::Util 'blessed';
use Carp         'confess';

use Moose::Exporter;

use Class::MOP 0.94;

use Moose::Meta::Class;
use Moose::Meta::TypeConstraint;
use Moose::Meta::TypeCoercion;
use Moose::Meta::Attribute;
use Moose::Meta::Instance;

use Moose::Object;

use Moose::Meta::Role;
use Moose::Meta::Role::Composite;
use Moose::Meta::Role::Application;
use Moose::Meta::Role::Application::RoleSummation;
use Moose::Meta::Role::Application::ToClass;
use Moose::Meta::Role::Application::ToRole;
use Moose::Meta::Role::Application::ToInstance;

use Moose::Util::TypeConstraints;
use Moose::Util ();

use Moose::Meta::Attribute::Native;

sub throw_error {
    # FIXME This
    shift;
    goto \&confess
}

sub extends {
    my $meta = shift;

    Moose->throw_error("Must derive at least one class") unless @_;

    # this checks the metaclass to make sure
    # it is correct, sometimes it can get out
    # of sync when the classes are being built
    $meta->superclasses(@_);
}

sub with {
    Moose::Util::apply_all_roles(shift, @_);
}

sub has {
    my $meta = shift;
    my $name = shift;

    Moose->throw_error('Usage: has \'name\' => ( key => value, ... )')
        if @_ % 2 == 1;

    my %options = ( definition_context => Moose::Util::_caller_info(), @_ );
    my $attrs = ( ref($name) eq 'ARRAY' ) ? $name : [ ($name) ];
    $meta->add_attribute( $_, %options ) for @$attrs;
}

sub before {
    Moose::Util::add_method_modifier(shift, 'before', \@_);
}

sub after {
    Moose::Util::add_method_modifier(shift, 'after', \@_);
}

sub around {
    Moose::Util::add_method_modifier(shift, 'around', \@_);
}

our $SUPER_PACKAGE;
our $SUPER_BODY;
our @SUPER_ARGS;

sub super {
    # This check avoids a recursion loop - see
    # t/100_bugs/020_super_recursion.t
    return if defined $SUPER_PACKAGE && $SUPER_PACKAGE ne caller();
    return unless $SUPER_BODY; $SUPER_BODY->(@SUPER_ARGS);
}

sub override {
    my $meta = shift;
    my ( $name, $method ) = @_;
    $meta->add_override_method_modifier( $name => $method );
}

sub inner {
    my $pkg = caller();
    our ( %INNER_BODY, %INNER_ARGS );

    if ( my $body = $INNER_BODY{$pkg} ) {
        my @args = @{ $INNER_ARGS{$pkg} };
        local $INNER_ARGS{$pkg};
        local $INNER_BODY{$pkg};
        return $body->(@args);
    } else {
        return;
    }
}

sub augment {
    my $meta = shift;
    my ( $name, $method ) = @_;
    $meta->add_augment_method_modifier( $name => $method );
}

Moose::Exporter->setup_import_methods(
    with_meta => [
        qw( extends with has before after around override augment )
    ],
    as_is => [
        qw( super inner ),
        \&Carp::confess,
        \&Scalar::Util::blessed,
    ],
);

sub init_meta {
    # This used to be called as a function. This hack preserves
    # backwards compatibility.
    if ( $_[0] ne __PACKAGE__ ) {
        return __PACKAGE__->init_meta(
            for_class  => $_[0],
            base_class => $_[1],
            metaclass  => $_[2],
        );
    }

    shift;
    my %args = @_;

    my $class = $args{for_class}
        or Moose->throw_error("Cannot call init_meta without specifying a for_class");
    my $base_class = $args{base_class} || 'Moose::Object';
    my $metaclass  = $args{metaclass}  || 'Moose::Meta::Class';

    Moose->throw_error("The Metaclass $metaclass must be a subclass of Moose::Meta::Class.")
        unless $metaclass->isa('Moose::Meta::Class');

    # make a subtype for each Moose class
    class_type($class)
        unless find_type_constraint($class);

    my $meta;

    if ( $meta = Class::MOP::get_metaclass_by_name($class) ) {
        unless ( $meta->isa("Moose::Meta::Class") ) {
            my $error_message = "$class already has a metaclass, but it does not inherit $metaclass ($meta).";
            if ( $meta->isa('Moose::Meta::Role') ) {
                Moose->throw_error($error_message . ' You cannot make the same thing a role and a class. Remove either Moose or Moose::Role.');
            } else {
                Moose->throw_error($error_message);
            }
        }
    } else {
        # no metaclass, no 'meta' method

        # now we check whether our ancestors have metaclass, and if so borrow that
        my ( undef, @isa ) = @{ $class->mro::get_linear_isa };

        foreach my $ancestor ( @isa ) {
            my $ancestor_meta = Class::MOP::get_metaclass_by_name($ancestor) || next;

            my $ancestor_meta_class = ($ancestor_meta->is_immutable
                ? $ancestor_meta->_get_mutable_metaclass_name
                : ref($ancestor_meta));

            # if we have an ancestor metaclass that inherits $metaclass, we use
            # that. This is like _fix_metaclass_incompatibility, but we can do it now.

            # the case of having an ancestry is not very common, but arises in
            # e.g. Reaction
            unless ( $metaclass->isa( $ancestor_meta_class ) ) {
                if ( $ancestor_meta_class->isa($metaclass) ) {
                    $metaclass = $ancestor_meta_class;
                }
            }
        }

        $meta = $metaclass->initialize($class);
    }

    if ( $class->can('meta') ) {
        # check 'meta' method

        # it may be inherited

        # NOTE:
        # this is the case where the metaclass pragma
        # was used before the 'use Moose' statement to
        # override a specific class
        my $method_meta = $class->meta;

        ( blessed($method_meta) && $method_meta->isa('Moose::Meta::Class') )
            || Moose->throw_error("$class already has a &meta function, but it does not return a Moose::Meta::Class ($method_meta)");

        $meta = $method_meta;
    }

    unless ( $meta->has_method("meta") ) { # don't overwrite
        # also check for inherited non moose 'meta' method?
        # FIXME also skip this if the user requested by passing an option
        $meta->add_method(
            'meta' => sub {
                # re-initialize so it inherits properly
                $metaclass->initialize( ref($_[0]) || $_[0] );
            }
        );
    }

    # make sure they inherit from Moose::Object
    $meta->superclasses($base_class)
      unless $meta->superclasses();

    return $meta;
}

# This may be used in some older MooseX extensions.
sub _get_caller {
    goto &Moose::Exporter::_get_caller;
}

## make 'em all immutable

$_->make_immutable(
    inline_constructor => 1,
    constructor_name   => "_new",
    # these are Class::MOP accessors, so they need inlining
    inline_accessors => 1
    ) for grep { $_->is_mutable }
    map { $_->meta }
    qw(
    Moose::Meta::Attribute
    Moose::Meta::Class
    Moose::Meta::Instance

    Moose::Meta::TypeCoercion
    Moose::Meta::TypeCoercion::Union

    Moose::Meta::Method
    Moose::Meta::Method::Accessor
    Moose::Meta::Method::Constructor
    Moose::Meta::Method::Destructor
    Moose::Meta::Method::Overridden
    Moose::Meta::Method::Augmented

    Moose::Meta::Role
    Moose::Meta::Role::Method
    Moose::Meta::Role::Method::Required
    Moose::Meta::Role::Method::Conflicting

    Moose::Meta::Role::Composite

    Moose::Meta::Role::Application
    Moose::Meta::Role::Application::RoleSummation
    Moose::Meta::Role::Application::ToClass
    Moose::Meta::Role::Application::ToRole
    Moose::Meta::Role::Application::ToInstance
);

1;

__END__

#line 1198
