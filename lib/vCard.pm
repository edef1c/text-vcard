package vCard;
use Moo;

use Path::Class;
use Text::vCard;
use vCard::AddressBook;

=head1 NAME

vCard - read, write, and edit a single vCard

=head1 SYNOPSIS

    use vCard;

    # create the object
    my $vcard = vCard->new;

    # there are 3 ways to load vcard data in one fell swoop 
    # (see method documentation for details)
    $vcard->load_file($filename); 
    $vcard->load_string($string); 
    $vcard->load_hashref($hashref); 

    # there are 3 ways to output data in vcard format
    my $file   = $vcard->as_file($filename); # writes to $filename
    my $string = $vcard->as_string;          # returns a string

    # simple getters/setters
    $vcard->full_name('Bruce Banner, PhD');
    $vcard->given_name('Bruce');
    $vcard->family_name('Banner');
    $vcard->title('Research Scientist');
    $vcard->photo('http://example.com/bbanner.gif');

    # complex getters/setters
    $vcard->phones({
        { type => ['work', 'text'], number => '651-290-1234', preferred => 1 },
        { type => ['home'],         number => '651-290-1111' }
    });
    $vcard->addresses({
        { type => ['work'], street => 'Main St' },
        { type => ['home'], street => 'Army St' },
    });
    $vcard->email_addresses({
        { type => ['work'], address => 'bbanner@ssh.secret.army.mil' },
        { type => ['home'], address => 'bbanner@timewarner.com'      },
    });


=head1 DESCRIPTION

A vCard is a digital business card.  vCard and L<vCard::AddressBook> provide an
API for parsing, editing, and creating vCards.

This module is built on top of L<Text::vCard>.  It provides a more intuitive user
interface.  

To handle an address book with several vCard entries in it, start with
L<vCard::AddressBook> and then come back to this module.

Note that the vCard RFC requires version() and full_name().  This module does
not check or warn if these conditions have not been met.


=head1 ENCODING AND UTF-8

See the 'ENCODING AND UTF-8' section of L<vCard::AddressBook>.


=head1 METHODS

=cut

has encoding_in  => ( is => 'rw', default => sub {'UTF-8'} );
has encoding_out => ( is => 'rw', default => sub {'UTF-8'} );
has _data        => ( is => 'rw', default => sub { { version => '4.0' } } );

=head2 load_hashref($hashref)

$hashref should look like this:

    full_name    => 'Bruce Banner, PhD',
    given_names  => ['Bruce'],
    family_names => ['Banner'],
    title        => 'Research Scientist',
    photo        => 'http://example.com/bbanner.gif',
    phones       => [
        { type => ['work'], number => '651-290-1234', preferred => 1 },
        { type => ['cell'], number => '651-290-1111' },
    },
    addresses => [
        { type => ['work'], ... },
        { type => ['home'], ... },
    ],
    email_addresses => [
        { type => ['work'], address => 'bbanner@shh.secret.army.mil' },
        { type => ['home'], address => 'bbanner@timewarner.com' },
    ],

Returns $self in case you feel like chaining.

=cut

sub load_hashref {
    my ( $self, $hashref ) = @_;
    $self->_data($hashref);
    $self->_data->{version} = '4.0' unless $self->_data->{version};
    return $self;
}

=head2 load_file($filename)

Returns $self in case you feel like chaining.

=cut

sub load_file {
    my ( $self, $filename ) = @_;
    return vCard::AddressBook    #
        ->new(
        {   encoding_in  => $self->encoding_in,
            encoding_out => $self->encoding_out,
        }
        )                         #
        ->load_file($filename)    #
        ->vcards->[0];
}

=head2 load_string($string)

Returns $self in case you feel like chaining.  This method assumes $string is
decoded (but not MIME decoded).

=cut

sub load_string {
    my ( $self, $string ) = @_;
    return vCard::AddressBook    #
        ->new(
        {   encoding_in  => $self->encoding_in,
            encoding_out => $self->encoding_out,
        }
        )->load_string($string)    #
        ->vcards->[0];
}

=head2 as_string()

Returns the vCard as a string.

=cut

sub as_string {
    my ($self) = @_;
    my $vcard = Text::vCard->new( { encoding_out => $self->encoding_out } );

    my $phones          = $self->_data->{phones};
    my $addresses       = $self->_data->{addresses};
    my $email_addresses = $self->_data->{email_addresses};

    $self->_build_simple_nodes( $vcard, $self->_data );
    $self->_build_name_node( $vcard, $self->_data );
    $self->_build_phone_nodes( $vcard, $phones ) if $phones;
    $self->_build_address_nodes( $vcard, $addresses ) if $addresses;
    $self->_build_email_address_nodes( $vcard, $email_addresses )
        if $email_addresses;

    return $vcard->as_string;
}

sub _simple_node_types {
    qw/full_name title photo birthday timezone version/;
}

sub _build_simple_nodes {
    my ( $self, $vcard, $data ) = @_;

    foreach my $node_type ( $self->_simple_node_types ) {
        if ( $node_type eq 'full_name' ) {
            next unless $data->{full_name};
            $vcard->fullname( $data->{full_name} );
        } else {
            next unless $data->{$node_type};
            $vcard->$node_type( $data->{$node_type} );
        }
    }
}

sub _build_name_node {
    my ( $self, $vcard, $data ) = @_;

    my $value = join ',', @{ $data->{family_names} || [] };
    $value .= ';' . join ',', @{ $data->{given_names}        || [] };
    $value .= ';' . join ',', @{ $data->{other_names}        || [] };
    $value .= ';' . join ',', @{ $data->{honorific_prefixes} || [] };
    $value .= ';' . join ',', @{ $data->{honorific_suffixes} || [] };

    $vcard->add_node( { node_type => 'N', data => [ { value => $value } ] } )
        if $value ne ';;;;';
}

sub _build_phone_nodes {
    my ( $self, $vcard, $phones ) = @_;

    foreach my $phone (@$phones) {

        # TODO: better error handling
        die "'number' attr missing from 'phones'" unless $phone->{number};
        die "'type' attr in 'phones' should be an arrayref"
            if ( $phone->{type} && ref( $phone->{type} ) ne 'ARRAY' );

        my $type      = $phone->{type} || [];
        my $preferred = $phone->{preferred};
        my $number    = $phone->{number};

        my $params = [];
        push @$params, { type => $_ } foreach @$type;
        push @$params, { pref => $preferred } if $preferred;

        $vcard->add_node(
            {   node_type => 'TEL',
                data      => [ { params => $params, value => $number } ],
            }
        );
    }
}

sub _build_address_nodes {
    my ( $self, $vcard, $addresses ) = @_;

    foreach my $address (@$addresses) {

        die "'type' attr in 'addresses' should be an arrayref"
            if ( $address->{type} && ref( $address->{type} ) ne 'ARRAY' );

        my $type = $address->{type} || [];
        my $preferred = $address->{preferred};

        my $params = [];
        push @$params, { type => $_ } foreach @$type;
        push @$params, { pref => $preferred } if $preferred;

        my $value = join ';',
            $address->{pobox}     || '',
            $address->{extended}  || '',
            $address->{street}    || '',
            $address->{city}      || '',
            $address->{region}    || '',
            $address->{post_code} || '',
            $address->{country}   || '';

        $vcard->add_node(
            {   node_type => 'ADR',
                data      => [ { params => $params, value => $value } ],
            }
        );
    }
}

sub _build_email_address_nodes {
    my ( $self, $vcard, $email_addresses ) = @_;

    foreach my $email_address (@$email_addresses) {

        # TODO: better error handling
        die "'address' attr missing from 'email_addresses'"
            unless $email_address->{address};
        die "'type' attr in 'email_addresses' should be an arrayref"
            if ( $email_address->{type}
            && ref( $email_address->{type} ) ne 'ARRAY' );

        my $type = $email_address->{type} || [];
        my $preferred = $email_address->{preferred};

        my $params = [];
        push @$params, { type => $_ } foreach @$type;
        push @$params, { pref => $preferred } if $preferred;

        # TODO: better error handling
        my $value = $email_address->{address};

        $vcard->add_node(
            {   node_type => 'EMAIL',
                data      => [ { params => $params, value => $value } ],
            }
        );
    }
}

=head2 as_file($filename)

Write data in vCard format to $filename.

Returns a L<Path::Class::File> object if successful.  Dies if not successful.

=cut

sub as_file {
    my ( $self, $filename ) = @_;

    my $file = ref $filename eq 'Path::Class::File'    #
        ? $filename
        : file($filename);

    my @iomode = $self->encoding_out eq 'none'         #
        ? ()
        : ( iomode => '>:encoding(' . $self->encoding_out . ')' );

    $file->spew( @iomode, $self->as_string, );

    return $file;
}

=head1 SIMPLE GETTERS/SETTERS

These methods accept and return strings.  

=head2 version()

Version number of the vcard.  Defaults to '4.0'

=head2 full_name()

A person's entire name as they would like to see it displayed.  

=head2 title()

A person's position or job.

=head2 photo()

This should be a link. TODO: handle binary image

=head2 birthday()

=head2 timezone()


=head1 COMPLEX GETTERS/SETTERS

These methods accept and return array references rather than simple strings.

=head2 family_names()

Accepts/returns an arrayref of family names (aka surnames).

=head2 given_names()

Accepts/returns an arrayref.

=head2 other_names()

Accepts/returns an arrayref of names which don't qualify as family_names or
given_names.

=head2 honorific_prefixes()

Accepts/returns an arrayref.  eg C<[ 'Dr.' ]>

=head2 honorific_suffixes()

Accepts/returns an arrayref.  eg C<[ 'Jr.', 'MD' ]>

=head2 phones()

Accepts/returns an arrayref that looks like:

  [
    { type => ['work'], number => '651-290-1234', preferred => 1 },
    { type => ['cell'], number => '651-290-1111' },
  ]

=head2 addresses()

Accepts/returns an arrayref that looks like:

  [
    { type => ['work'], street => 'Main St', preferred => 1 },
    { type => ['home'], street => 'Army St' },
  ]

=head2 email_addresses()

Accepts/returns an arrayref that looks like:

  [
    { type => ['work'], address => 'bbanner@ssh.secret.army.mil' },
    { type => ['home'], address => 'bbanner@timewarner.com', preferred => 1 },
  ]

=cut

sub version            { shift->setget( 'version',            @_ ) }
sub full_name          { shift->setget( 'full_name',          @_ ) }
sub family_names       { shift->setget( 'family_names',       @_ ) }
sub given_names        { shift->setget( 'given_names',        @_ ) }
sub other_names        { shift->setget( 'other_names',        @_ ) }
sub honorific_prefixes { shift->setget( 'honorific_prefixes', @_ ) }
sub honorific_suffixes { shift->setget( 'honorific_suffixes', @_ ) }
sub title              { shift->setget( 'title',              @_ ) }
sub photo              { shift->setget( 'photo',              @_ ) }
sub birthday           { shift->setget( 'birthday',           @_ ) }
sub timezone           { shift->setget( 'timezone',           @_ ) }
sub phones             { shift->setget( 'phones',             @_ ) }
sub addresses          { shift->setget( 'addresses',          @_ ) }
sub email_addresses    { shift->setget( 'email_addresses',    @_ ) }

sub setget {
    my ( $self, $attr, $value ) = @_;
    $self->_data->{$attr} = $value if $value;
    return $self->_data->{$attr};
}

=head1 AUTHOR

Eric Johnson (kablamo), github ~!at!~ iijo dot org

=head1 ACKNOWLEDGEMENTS

Thanks to L<Foxtons|http://foxtons.co.uk> for making this module possible by
donating a significant amount of developer time.

=cut

1;
