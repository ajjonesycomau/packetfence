package pf::SNMP::HP::Controller_MSM710;

=head1 NAME

pf::SNMP::HP::Controller_MSM710

=head1 SYNOPSIS

The pf::SNMP::HP::Controller_MSM710 module manages access to HP Procurve Controller MSM710

=head1 STATUS

Should work on all HP Wireless E series

=cut

use strict;
use warnings;
use diagnostics;

use Log::Log4perl;
use POSIX;

use base ('pf::SNMP::HP');

use pf::config;
# importing switch constants
use pf::SNMP::constants;
use pf::util;

=head1 SUBROUTINES

=over

=cut

# CAPABILITIES
# access technology supported
sub supportsWirelessDot1x { return $TRUE; }
sub supportsWirelessMacAuth { return $TRUE; }

=item getVersion - obtain image version information from switch

=cut

sub getVersion {
    my ($this)       = @_;
    my $oid_sysDescr = '1.3.6.1.2.1.1.1.0'; #SNMPv2-MIB
    my $logger       = Log::Log4perl::get_logger( ref($this) );
    if ( !$this->connectRead() ) {
        return '';
    }
    $logger->trace("SNMP get_request for sysDescr: $oid_sysDescr");
    my $result = $this->{_sessionRead}->get_request( -varbindlist => [$oid_sysDescr] );
    my $sysDescr = ( $result->{$oid_sysDescr} || '' );
    if ( $sysDescr =~ m/V(\d{1}\.\d{2}\.\d{2})/ ) {
        return $1;
    } elsif ( $sysDescr =~ m/Version (\d+\.\d+\([^)]+\)[^,\s]*)(,|\s)+/ ) {
        return $1;
    } else {
        return $sysDescr;
    }
}

=item parseTrap - interpret traps and populate a trap hash 

=cut

sub parseTrap {
    my ( $this, $trapString ) = @_;
    my $trapHashRef;
    my $logger = Log::Log4perl::get_logger( ref($this) );

    # COLUBRIS-DEVICE-EVENT-MIB :: coDeviceEventSuccessfulDeAuthentication :: 1.3.6.1.4.1.8744.5.26.2.0.9
    # COLUBRIS-DEVICE-EVENT-MIB :: coDevEvDetMacAddress ::                    1.3.6.1.4.1.8744.5.26.1.2.2.1.2

    if ( $trapString =~ /\.1\.3\.6\.1\.4\.1\.8744\.5\.26\.2\.0\.9[|]\.1\.3\.6\.1\.4\.1\.8744\.5\.26\.1\.2\.2\.1\.2.+$SNMP::MAC_ADDRESS_FORMAT/ ) {

        $trapHashRef->{'trapType'} = 'dot11Deauthentication';
        $trapHashRef->{'trapMac'} = parse_mac_from_trap($1);

    } else {
        $logger->debug("trap currently not handled");
        $trapHashRef->{'trapType'} = 'unknown';
    }
    return $trapHashRef;
}

=item deauthenticateMac - deauthenticate a MAC address from wireless network (including 802.1x) through SNMP

=cut

sub deauthenticateMac {
    my ($this, $mac) = @_;
    my $logger = Log::Log4perl::get_logger(ref($this));
    my $OID_coDevWirCliStaMACAddress = '1.3.6.1.4.1.8744.5.25.1.7.1.1.2'; # from COLUBRIS-DEVICE-WIRELESS-MIB
    my $OID_coDevWirCliDisassociate = '1.3.6.1.4.1.8744.5.25.1.7.1.1.27'; # from COLUBRIS-DEVICE-WIRELESS-MIB

    if ( !$this->connectWrite() ) {
        return '';
    }

    # Query the controller to get the index of the MAc in the coDeviceWirelessClientStatusTable 
    # CAUTION: we need to use the sessionWrite in order to have access to that table
    $logger->trace("SNMP get_table for coDevWirCliStaMACAddress: $OID_coDevWirCliStaMACAddress");
    my $result = $this->{_sessionWrite}->get_table(-baseoid => "$OID_coDevWirCliStaMACAddress");
    if (keys %{$result}) {
        my $count = 0;
        foreach my $key ( keys %{$result} ) {
            $result->{$key} =~ /0x([A-Z0-9]{2})([A-Z0-9]{2})([A-Z0-9]{2})([A-Z0-9]{2})([A-Z0-9]{2})([A-Z0-9]{2})/i;
            my $coDevWirCliStaMACAddress = "$1:$2:$3:$4:$5:$6";
            if ($coDevWirCliStaMACAddress eq $mac) {
                $key =~ /^$OID_coDevWirCliStaMACAddress\.(\d+).(\d+).(\d+)$/;
                my $coDevWirCliStaIndex = "$1.$2.$3";

                $logger->debug("deauthenticating $mac on controller " . $this->{_ip});
                $logger->trace("SNMP set_request for coDevWirCliDisassociate: 
                    $OID_coDevWirCliDisassociate.$coDevWirCliStaIndex = $HP::DISASSOCIATE"
                );
                $result = $this->{_sessionWrite}->set_request(-varbindlist => [
                    "$OID_coDevWirCliDisassociate.$coDevWirCliStaIndex", Net::SNMP::INTEGER, $HP::DISASSOCIATE
                ]);
                $count++;
                last;
            }
        }
        if ($count == 0) {
            $logger->warn("Can not deauthenticate $mac on controller " . $this->{_ip} . " because it does not seem to be associated!");
        }
    } else {
        $logger->error("Can not get the list of associated devices on controller " . $this->{_ip});
    }
}

=item extractSsid

Find RADIUS SSID parameter out of RADIUS REQUEST parameters

HP / Colubris specific parser. See pf::SNMP for base implementation.

=cut
sub extractSsid {
    my ($this, $radius_request) = @_;
    my $logger = Log::Log4perl::get_logger(ref($this));

    if (defined($radius_request->{'Colubris-AVPair'})) {
        # With HP Procurve AP Ccontroller, we receive an array of settings in Colubris-AVPair:
        # Colubris-AVPair = ssid=Inv_Controller
        # Colubris-AVPair = group=Default Group
        # Colubris-AVPair = phytype=IEEE802dot11g
        foreach (@{$radius_request->{'Colubris-AVPair'}}) {
            if (/^ssid=(.*)$/) { return $1; }
        }
        $logger->info("Unable to extract SSID of Colubris-AVPair: ".@{$radius_request->{'Colubris-AVPair'}});
    }

    $logger->warn(
        "Unable to extract SSID for module " . ref($this) . ". SSID-based VLAN assignments won't work. "
        . "Please let us know so we can add support for it."
    );
    return;
}

=back

=head1 AUTHOR

Regis Balzard <rbalzard@inverse.ca>

Olivier Bilodeau <obilodeau@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2010-2011 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

1;

# vim: set shiftwidth=4:
# vim: set expandtab:
# vim: set backspace=indent,eol,start:
