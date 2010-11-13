package Business::FedEx::RateRequest;

use 5.008008;
use strict;
use warnings;

require Exporter;

use LWP::UserAgent;
use XML::Simple;
use Data::Dumper; 

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Business::FedEx::RateRequest ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw();

our $VERSION = '0.94';

# FedEx Shipping notes
our %ship_note;
$ship_note{'FEDEX SAMEDAY'} = 'Fastest\t Delivery time based on flight availability';
$ship_note{'FIRST_OVERNIGHT'} = 'Overnight\t 	Delivery by 8:00 or 8:30 am';										
$ship_note{'PRIORITY_OVERNIGHT'} = 'Overnight\t Delivery by10:30 am';
$ship_note{'STANDARD_OVERNIGHT'} = 'Overnight\n Delivery by 3:00 pm';															
$ship_note{'FEDEX_2_DAY'} = '2 Business Days\t Delivery by 4:30 pm';
$ship_note{'FEDEX_EXPRESS_SAVER'} = '3 Business Days\t 	Delivery by 4:30 pm';	
$ship_note{'FEDEX_GROUND'} = '1–5 Business Days\t	Delivery day based on distance to destination';	
$ship_note{'FEDEX_HOME_DELIVERY'} = '1–5 Business Days\t Delivery day based on distance to destination';				

$ship_note{'INTERNATIONAL_NEXT_FLIGHT'} = 'Fastest\t Delivery time based on flight availability';
$ship_note{'INTERNATIONAL_FIRST'}   = '2 Business Days\t Delivery by 8:00 or 8:30 am to select European cities';
$ship_note{'INTERNATIONAL_PRIORITY'}= '1–3 Business Days\t Delivery time based on country';
$ship_note{'INTERNATIONAL_ECONOMY'} = '2–5 Business Days\t Delivery time based on country';
$ship_note{'INTERNATIONAL_GROUND'}	= '3–7 Business Days\t Delivery to Canada and Puerto Rico';


# Preloaded methods go here.

sub new {

    my $name = shift;
    my $class = ref($name) || $name;

    my %args = @_;

    my $self  = {
                 uri => $args{'uri'},
                 account  => $args{'account'},
                 meter    =>  $args{'meter'},
                 key      =>  $args{'key'},
                 password =>  $args{'password'},
                 err_msg =>    "",
                };

    my @rqd_lst = qw/uri meter account key password/; 
    foreach my $param (@rqd_lst) { unless ( $args{$param} ) { $self->{'err_msg'}="$param required"; return 0; } }

    $self->{UA} = LWP::UserAgent->new(agent => 'perlworks');
    #$self->{REQ} = HTTP::Request->new(POST=>$self->{uri}); # Create a request

    bless ($self, $class);
}

# - - - - - - - - - - - - - - -
sub get_rates
{
	my $self = shift @_;
	my %args = @_;

   my @rqd_lst = qw/src_zip dst_zip weight/;    
   foreach my $param (@rqd_lst) { unless ( $args{$param} ) { $self->{'err_msg'}="$param required"; return 0; } }

   unless ( $args{'src_country'}  ) { $args{'src_country'} = 'US' }  
   unless ( $args{'dst_country'}  ) { $args{'dst_country'} = 'US' } 
   unless ( $args{'weight_units'} ) { $args{'weight_units'} = 'LB'} 
   unless ( $args{'size_units'}   ) { $args{'lnght_units'} = 'IN' } 
   unless ( $args{'length'}       ) { $args{'length'} = '5' } 
   unless ( $args{'width'}        ) { $args{'width'}  = '5' } 
   unless ( $args{'height'}       ) { $args{'height'} = '5' } 

   my $xml_snd_doc = $self->gen_xml(\%args); 

	#print $xml_snd_doc; exit; 

	my $response = $self->{UA}->post($self->{'uri'}, Content_Type=>'text/xml', Content=>$xml_snd_doc);

	unless ($response->is_success) 
	{
		$self->{'err_msg'} = "Error Request: " . $response->status_line;
      return 0; 
   }
  
   # Must be success let's parse 

	my $rtn = $response->as_string;
 	$rtn =~ /(.*)\n\n(.*)/s;
   
	my $hdr = $1;  # Don't use for anything right now
   my $xml_rtn_doc = $2; # The object of this all.... 

	my $xml_obj  = new XML::Simple;    

   my $data = $xml_obj->XMLin($xml_rtn_doc); # Time consuming operation. could use a regexp to speed up if necessary. 
        
   #print $response->as_string; exit; # Debug 

   my $rate_lst_ref = $data->{'v9:RateReplyDetails'};
     
   my @rtn_lst; # This will be returned

   my $i = 0; 
	foreach my $detail_ref ( @{$rate_lst_ref} )
	{
   	my $ah_ref = $detail_ref->{'v9:RatedShipmentDetails'};
      my $ship_cost; 
      
      if ( ref($ah_ref) eq 'ARRAY' ) 
      {
			$ship_cost = $ah_ref->[0]->{'v9:ShipmentRateDetail'}->{'v9:TotalNetCharge'}->{'v9:Amount'};
      }
      else
		{
			$ship_cost = $ah_ref->{'v9:ShipmentRateDetail'}->{'v9:TotalNetCharge'}->{'v9:Amount'};
		}

  		my $ServiceType = $detail_ref->{'v9:ServiceType'};

      # Tags
  		my $tag = lc($ServiceType);
      $tag =~ s/_/ /g;
      $tag =~ s/\b(\w)/\U$1/g;

		# Notes
      my $note = $ship_note{"$ServiceType"};

      $rtn_lst[$i] = {'ServiceType'=>$ServiceType, 'ship_cost'=>$ship_cost, 'ship_tag'=>$tag, 'ship_note'=>$note};
      $i++;  
   }
   
   return wantarray ? @rtn_lst : \@rtn_lst;
 }

# - - - - - - - - - - - - - - -
sub gen_xml
{
   my $self = shift; 
	my $args = shift;

	my $rqst = <<END;
<?xml version="1.0" encoding="utf-8"?>
<RateRequest xmlns="http://fedex.com/ws/rate/v9">
  <WebAuthenticationDetail>
    <UserCredential>
      <Key>$self->{'key'}</Key>
      <Password>$self->{'password'}</Password> 	
    </UserCredential>
  </WebAuthenticationDetail>
  <ClientDetail>
    <AccountNumber>$self->{'account'}</AccountNumber>
    <MeterNumber>$self->{'meter'}</MeterNumber>
  </ClientDetail>
  <TransactionDetail>
    <CustomerTransactionId>Perlworks</CustomerTransactionId>
  </TransactionDetail>
  <Version>
    <ServiceId>crs</ServiceId>
    <Major>9</Major>
    <Intermediate>0</Intermediate>
    <Minor>0</Minor>
  </Version>
  <RequestedShipment>
    <ShipTimestamp>2010-08-20T09:30:47-05:00</ShipTimestamp>
    <DropoffType>REGULAR_PICKUP</DropoffType>
    <PackagingType>YOUR_PACKAGING</PackagingType>
    <Shipper>
      <AccountNumber>$self->{'account'}</AccountNumber>
      <Address>
        <PostalCode>$args->{'src_zip'}</PostalCode>
        <CountryCode>$args->{'src_country'}</CountryCode>
      </Address>
    </Shipper>
    <Recipient>
      <Address>
        <PostalCode>$args->{'dst_zip'}</PostalCode>
        <CountryCode>$args->{'dst_country'}</CountryCode>
      </Address>
    </Recipient>
    <ShippingChargesPayment>
      <PaymentType>SENDER</PaymentType>
      <Payor>
        <AccountNumber>$self->{'account'}</AccountNumber>
        <CountryCode>USD</CountryCode>
      </Payor>
    </ShippingChargesPayment>
    <RateRequestTypes>ACCOUNT</RateRequestTypes>
    <PackageCount>1</PackageCount>
    <PackageDetail>INDIVIDUAL_PACKAGES</PackageDetail>
    <RequestedPackageLineItems>
      <SequenceNumber>1</SequenceNumber>
      <Weight>
        <Units>LB</Units>
        <Value>$args->{'weight'}</Value>
      </Weight>
      <Dimensions>
        <Length>$args->{'length'}</Length>
        <Width>$args->{'width'}</Width>
        <Height>$args->{'height'}</Height>
        <Units>IN</Units>
      </Dimensions>
    </RequestedPackageLineItems>
  </RequestedShipment>
</RateRequest>
END

  #$rqst =~ s/\n//g;
  return $rqst;
}

sub err_msg
{
  my $self = shift @_; 
  return $self->{err_msg}; 
}


# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Business::FedEx::RateRequest - Perl extension for getting available rates from Fedex using their Web Services API. 

=head1 SYNOPSIS

	use Business::FedEx::RateRequest;

	use Data::Dumper;

	# Get your account/meter/key/password numbers from Fedex 
	my %rate_args; 
	$rate_args{'account'}  = '_your_account_number_'; 
	$rate_args{'meter'}    = '_your_meter_number_';  
	$rate_args{'key'}      = '_your_key_';
	$rate_args{'password'} = '_your_password_';

	$rate_args{'uri'}      = 'https://gatewaybeta.fedex.com:443/xml/rate';

	my $Rate = new Business::FedEx::RateRequest(%rate_args);

	my %ship_args;
	$ship_args{'src_zip'} = '83835'; 
	$ship_args{'dst_zip'} = '55411'; 
	$ship_args{'weight'} = 5; 

	my $rtn = $Rate->get_rates(%ship_args);

	if ( $rtn )	{ print Dumper $rtn }
	else        { print $Rate->err_msg() }  

Should return something like

	$VAR1 = [
          {
            'ship_cost' => '112.93',
            'ServiceType' => 'FIRST_OVERNIGHT'
          },
          {
            'ship_cost' => '48.91',
            'ServiceType' => 'PRIORITY_OVERNIGHT'
          },
          {
            'ship_cost' => '75.04',
            'ServiceType' => 'STANDARD_OVERNIGHT'
          },
          {
            'ship_cost' => '42.84',
            'ServiceType' => 'FEDEX_2_DAY'
          },
          {
            'ship_cost' => '28.81',
            'ServiceType' => 'FEDEX_EXPRESS_SAVER'
          },
          {
            'ship_cost' => '7.74',
            'ServiceType' => 'FEDEX_GROUND'
          }
        ];


=head1 DESCRIPTION

This object uses a simple XML/POST instead of the slower and more complex Soap based method to obtain 
available rates between two zip codes for a given package weight and size.  At the time of this writing 
FedEx evidently encourages the use of Soap to get available rates and provides source code examples for 
Java, PHP, C# but no Perl. FedEx doesn't provide non-Soap XML examples that I could find. Took me a 
while to develop the XML request but it returns results faster than the PHP Soap method.

The XML returned is voluminous, over 30k bytes to return a few rates, but is smaller 
than the comparable Soap results.

The URI's are not published anywhere I could find but I was successful in using  

Test:		https://gatewaybeta.fedex.com:443/xml/rate 
Production:	https://gateway.fedex.com:443/xml

Early Beta modules and notes may be available at:  

http://perlworks.com/cpan

If you use this module and have comments or suggestions please let me know.  

=head1 METHODS

=over 4

=item $obj->new(%hash)

The new method is the constructor.  

The input hash must include the following:

   uri 		=> FedEx URI (test or production)      	  
   account 	=> FedEx Account    
   meter 	=> FedEx Meter Number     	  
   key 		=> FedEx Key        
   password => FedEx Password   

=item $obj->get_rates(%hash)

The input must include the following 

  	src_zip => Source Zip Code 
	dst_zip => Source Zip Code
	weight  => Package weight in lbs

However the following are optionally and can override the defaults as noted

   unless ( $args{'src_country'}  ) { $args{'src_country'} = 'US' }  
   unless ( $args{'dst_country'}  ) { $args{'dst_country'} = 'US' } 
   unless ( $args{'weight_units'} ) { $args{'weight_units'} = 'LB'} 
   unless ( $args{'size_units'}   ) { $args{'lnght_units'} = 'IN' } 
   unless ( $args{'length'}       ) { $args{'length'} = '5' } 
   unless ( $args{'width'}        ) { $args{'width'}  = '5' } 
   unless ( $args{'height'}       ) { $args{'height'} = '5' } 

=item $obj->err_msg()

=back

Returns last posted error message. Usually checked after a 
false return from one of the methods above. 

=head1 EXPORT

None by default.

=head1 SEE ALSO

Business::FedEx::DirectConnect may work but I could not find the URI to use with this 
method and I found out that the Ship Manager API is depreciated and will be turned 
off in 2012 

=head1 AUTHOR

Steve Troxel, E<lt>troxel @ REMOVEMEperlworks.com E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Steven Troxel 

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
