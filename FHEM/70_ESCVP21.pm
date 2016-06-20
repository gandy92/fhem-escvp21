##############################################
#
# A module to control Epson projectors via ESC/VP21
#
# written 2013 by Henryk Ploetz <henryk at ploetzli.ch>
#
# The information is based on epson322270eu.pdf and later epson373739eu.pdf
# Some details from pl600pcm.pdf were used, but this enhanced support is not
# complete.
#
# Extended 2016 by Andy Thaller according to epson375633eu.xlsx
#
##############################################
# Definition: define <name> ESCVP21 <port> [<model>]
# Parameters:
#    port - Specify the serial port your projector is connected to, e.g. /dev/ttyUSB0
#           (For consistent naming, look into /dev/serial/by-id/ )
#           Optionally can specify the baud rate, e.g. /dev/ttyUSB0@9600
#   model - Specify the model of your projector, e.g. tw3000 (case insensitive)
#
#	15.01.15	Add new Models for Input: EH-TW5900 / EH-TW6000 / EH-TW6000W
#	23.01.15	Add Readings: serial number / Luminance (00:Normal-30:Auto-40:Full-50:Zoom-70:Wide) / Aspect (00:Normal-01:Eco)


package main;

use strict;
use warnings;
use POSIX;
##use DevIo;

my @ESCVP21_SOURCES = (
  ['10', "cycle1"],
  ['11', "analog-rgb1"],
  ['12', "digital-rgb1"],
  ['13', "rgb-video1"],
  ['14', "ycbcr1"],
  ['15', "ypbpr1"],
  ['1f', "auto1"],
  ['20', "cycle2"],
  ['21', "analog-rgb2"],
  ['22', "rgb-video2"],
  ['23', "ycbcr2"],
  ['24', "ypbpr2"],
  ['25', "ypbpr2"],
  ['2f', "auto2"],
  ['30', "cycle3"],
  ['31', "digital-rgb3"],
  ['33', "rgb-video3"],
  ['34', "ycbcr3"],
  ['35', "ypbpr3"],
  ['c0', "cycle5"],
  ['c3', "scart5"],
  ['c4', "ycbcr5"],
  ['c5', "ypbpr5"],
  ['cf', "auto5"],
  ['40', "cycle4"],
  ['41', "video-rca4"],
  ['42', "video-s4"],
  ['43', "video-ycbcr4"],
  ['44', "video-ypbpr4"],
  ['52', "usb-easymp"],
  ['a0', "hdmi2"],
  ['a1', "digital-rgb-hdmi"],
  ['a3', "rgb-video-hdmi"],
  ['a4', "ycbcr-hdmi"],
  ['a5', "ypbpr-hdmi"],
  ['d0', "wirelesshd"],
  ['d1', "digital-rgb-hdmi-2"],
  ['d3', "rgb-video-hdmi-2"],
  ['d4', "ycbcr-hdmi-2"],
  ['d5', "ypbpr-hdmi-2"],
);

my @ESCVP21_SOURCES_OVERRIDE = (
  # From documentation
  ['tw[12]0', [
      ['14', "component1"],
      ['15', "component1"],
    ]
  ],
  ['tw500', [
      ['23', "rgb-video2"],
      ['24', "ycbcr2"],
    ]
  ],
  # From experience
  ['tw[05]00', [
      ['30', "hdmi1"],
    ]
  ],
  ['tw(5900|6000|6000w)', [
      ['10', "component-cycle"],
      ['14', "component-ycbcr"],
      ['15', "component-ypbpr"],
      ['1f', "component-auto"],
      ['20', "pc-cycle"],
      ['21', "pc-analog-rgb"],
      ['30', "hdmi1"],
      ['40', "video-cycle"],
      ['41', "video-rca"],
    ]
  ],

 );

my @ESCVP21_SOURCES_AVAILABLE = (
  ['tw100h?', ['10', '11', '20', '21', '23', '24', '31', '40', '41', '42', '43', '44']],
  ['ts10', ['10', '11', '12', '13', '20', '21', '22', '23', '24', '40', '41', '42']],
  ['tw10h?', ['10', '13', '14', '15', '20', '21', '40', '41', '42']],
  ['tw200h?', ['10', '13', '14', '15', '20', '21', 'c0', 'c4', 'c5', '40', '41', '42']],
  ['tw500', ['10', '11', '13', '14', '15', '1f', '20', '21', '23', '24', '25', '2f', '30', 'c0', 'c4', 'c5', 'cf', '40', '41', '42']],
  ['tw20', ['10', '13', '14', '15', '20', '21', '40', '41', '42']],
  ['tw(600|520|550|800|700|1000)', ['10', '14', '15', '1f', '20', '21', '30', 'c0', 'c3', 'c4', 'c5', 'cf', '40', '41', '42']],
  ['tw2000', ['10', '14', '15', '1f', '20', '21', '30', 'a0', '40', '41', '42']],
  ['tw([345]000|3500)', ['10', '14', '15', '1f', '20', '21', '30', 'a0', '40', '41', '42']],
  ['tw420', ['10', '11', '14', '1f', '30', '41', '42']],
  ['tw(5900|6000|6000w)', ['10', '14', '15', '1f', '20', '21', '30', '31', '33', '34', '35', '40', '41', '52', 'a0', 'a1', 'a3', 'a4', 'a5', 'd0', 'd1', 'd3', 'd4', 'd5']],
);

my @ESCVP21_REMOTE = (
  ['03', "Menü"],
  ['05', "ESC"],
  ['14', "Auto"],
  ['16', "Enter"],
  ['35', "UP"],
  ['36', "Down"],
  ['37', "Left"],
  ['38', "Right"],
  ['48', "Source"],
);

my @ESCVP21_REMOTE_OVERRIDE = (
  # From documentation
 );

my @ESCVP21_REMOTE_AVAILABLE = (
  ['tw(5900|6000|6000w)', ['03', '05', '14', '16', '35', '36', '37', '38', '48']],
);

# see epson375633eu.xlsx
my %ESCVP21_ERROR_COCES = (
  '00' => 'There is no error or the error is recovered',
  '01' => 'Fan error',
  '03' => 'Lamp failure at power on',
  '04' => 'High internal temperature error',
  '06' => 'Lamp error',
  '07' => 'Open Lamp cover door error',
  '08' => 'Cinema filter error',
  '09' => 'Electric dual-layered capacitor is disconnected',
  '0A' => 'Auto iris error',
  '0B' => 'Subsystem Error',
  '0C' => 'Low air flow error',
  '0D' => 'Air filter air flow sensor error',
  '0E' => 'Power supply unit error (Ballast)',
  '0F' => 'Shutter error',
  '10' => 'Cooling system error (peltier element)',
  '11' => 'Cooling system error (Pump)',
  '12' => 'Static iris error',
  '13' => 'Power supply unit error (Disagreement of Ballast)',
  '14' => 'Exhaust shutter error',
  '15' => 'Obstacle detection error',
  '16' => 'IF board discernment error',
);

# see epson375633eu.xlsx
#
# Projector executes commands normally while a warning indicator 
# such as a high temperature warning is on.
# Projector does not execute commands nor return a colon when the 
# projector is in an abnormal state such as a lamp failure and 
# abnormal high temperature.
#
# When an abnormal state is continued for 130 seconds after,
# PWR ON command becomes possible.
#
my %ESCVP21_STATUS_COCES = (
  '00' => 'Standy',
  '01' => 'Lamp On',
  '02' => 'Warmup',
  '03' => 'Cooldown',
  '05' => 'Abnormality standby',
);

sub ESCVP21_Initialize($$)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  $hash->{DefFn}    = "ESCVP21_Define";
  $hash->{SetFn}    = "ESCVP21_Set";
  $hash->{ReadFn}   = "ESCVP21_Read";  
  $hash->{ReadyFn}  = "ESCVP21_Ready";
  $hash->{UndefFn}  = "ESCVP21_Undefine";
  $hash->{AttrList} = "TIMER" . $readingFnAttributes; # "event-on-update-reading event-on-change-reading stateFormat webCmd devStateIcon"
  $hash->{fhem}{interfaces} = "switch_passive;switch_active";
  
}

sub ESCVP21_Define($$)
{
  my ($hash, $def) = @_;
  ##DevIo_CloseDev($hash);
  my @args = split("[ \t]+", $def);
  if (int(@args) < 2) {
    return "Invalid number of arguments: define <name> ESCVP21 <port> [<model> [<timer>]]";
  }
  DevIo_CloseDev($hash);

  my ($name, $type, $port, $model, $timer) = @args;
  $model = "unknown" unless defined $model;
  $timer = 30 unless defined $timer;
  $hash->{Model} = lc($model);
  $hash->{DeviceName} = $port;
  $hash->{CommandQueue} = '';
  $hash->{ActiveCommand} = '';
  $hash->{Timer} = $timer;
  $hash->{STATE} = 'Initialized';

  my %table = ESCVP21_SourceTable($hash);
  $hash->{SourceTable} = \%table;
  $attr{$hash->{NAME}}{webCmd} = "on:off:input";
  $attr{$hash->{NAME}}{devStateIcon} = "on-.*:on:off mute-.*:muted:mute off:off:on";

  my $dev;
  my $baudrate;
  ($dev, $baudrate) = split("@", $port);
  $readyfnlist{"$name.$dev"} = $hash;

  my $ret = DevIo_OpenDev($hash, 0, "ESCVP21_Init");
  return $ret;
}

sub ESCVP21_Ready($)
{
  my ($hash) = @_;
  return DevIo_OpenDev($hash, 0, "ESCVP21_Init")
    if ($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only (seen in 34_panStamp.pm on 19.08.2014)
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes>0);
}

sub ESCVP21_Undefine($$)
{
  my ($hash,$arg) = @_;
  my $name = $hash->{NAME};
  RemoveInternalTimer("watchdog:".$name);
  RemoveInternalTimer("getStatus:".$name);
  DevIo_CloseDev($hash);
  return undef;
}

sub ESCVP21_Init($)
{
  my ($hash) = @_;
  my $time = gettimeofday();
  $hash->{CommandQueue} = '';
  $hash->{ActiveCommand} = "init";
  ESCVP21_Command($hash,"");
  ESCVP21_ArmWatchdog($hash);

  return undef;
}

sub ESCVP21_ArmWatchdog($)
{
  my ($hash) = @_;
  my $time = gettimeofday();
  my $name = $hash->{NAME};

  Log 5, "ESCVP21_ArmWatchdog: Watchdog disarmed";
  RemoveInternalTimer("watchdog:".$name);

  if($hash->{ActiveCommand}) {
    my $timeout;
    if($hash->{ActiveCommand} =~ /^power(On|Off)$/) {
      # Power commands take a while
      $timeout = 60;
    } elsif($hash->{ActiveCommand} =~ /^SOURCE/) {
      # Source changes may incorporate autoadjust and also take some time
      $timeout = 5;
    } else {
      # All others should be faster
      $timeout = 3;
    }

    Log 5, "ESCVP21_ArmWatchdog: Watchdog armed for $timeout seconds";
    InternalTimer($time + $timeout, "ESCVP21_Watchdog", "watchdog:".$name, 0);
  }
}

sub ESCVP21_Watchdog($)
{
  my($in) = shift;
  my(undef,$name) = split(':',$in);
  my $hash = $defs{$name};
 
  Log 4, "ESCVP21_Watchdog: called for command '$hash->{ActiveCommand}', resetting communication";
 
  ESCVP21_Queue($hash, $hash->{ActiveCommand}, 1) unless $hash->{ActiveCommand} =~ /^init/;
 
  my $command_queue_saved = $hash->{CommandQueue};
  ESCVP21_Init($hash);
  $hash->{CommandQueue} = $command_queue_saved;
}

sub ESCVP21_Read($)
{
  my ($hash) = @_;
  my $buffer = '';
  my $line = undef;
  if(defined($hash->{PARTIAL}) && $hash->{PARTIAL}) {
    $buffer = $hash->{PARTIAL} . DevIo_SimpleRead($hash);
  } else {
    $buffer = DevIo_SimpleRead($hash);
  }

  ($line, $buffer) = ESCVP21_Parse($buffer);
  while($line) {
    Log 4, "ESCVP21_Read (" . $hash->{ActiveCommand} . ") '$line'";

    # When we get a state response, update the corresponding reading
    if($line =~ /([^=]+)=([^=]+)/) {
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, $1, $2) unless $hash->{READINGS}{$1}{VAL} eq $2;
      ESCVP21_UpdateState($hash);
      readingsEndUpdate($hash, 1);
    }

    my $last_command = $hash->{ActiveCommand};

    if($hash->{ActiveCommand} eq "init") {
      # Wait for the first colon response
      if($line eq ":") {
	$hash->{ActiveCommand} = "initPwr";
	ESCVP21_Command($hash,"PWR?");
      }
    } elsif ($hash->{ActiveCommand} eq "initPwr") {
      # Wait for the first PWR state response
      if($line =~ /^PWR=.*/) {
	$hash->{ActiveCommand} = "";
	
	# Done initialising, begin polling for status
	ESCVP21_GetStatus($hash);
      }
    } elsif($line eq ":") {
      # When we get a colon prompt, the current command finished
      $hash->{ActiveCommand} = "";
    }

    if($line eq "ERR" and not $last_command eq "getERR") {
      # Insert an error query into the queue
      ESCVP21_Queue($hash,"getERR",1);
    }

    if($line eq ":") {
      ESCVP21_IssueQueuedCommand($hash);
    }

    ESCVP21_ArmWatchdog($hash);
 
    ($line, $buffer) = ESCVP21_Parse($buffer);
  }

  $hash->{PARTIAL} = $buffer;
  Log 5, "ESCVP21_Read-Tail '$buffer'";
}

sub ESCVP21_Parse($@)
{
  my $msg = undef;
  my ($tail) = @_;
 
  if($tail =~ /^(.*?)(:|\x0d)(.*)$/s) {
    if($2 eq ":") {
      $msg = $1 . $2;
    } else {
      $msg = $1;
    }
    $tail = $3;
  }

  return ($msg, $tail);
}


sub ESCVP21_GetStatus($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log 5, "ESCVP21_GetStatus called for $name";

  RemoveInternalTimer("getStatus:".$name);
 
  # Only queue commands when the queue is empty, otherwise, try again in a few seconds
  if(!$hash->{CommandQueue}) {
    InternalTimer(gettimeofday()+$hash->{Timer}, "ESCVP21_GetStatus_t", "getStatus:".$name, 0);

    ESCVP21_QueueGet($hash,"VOL");
    ESCVP21_QueueGet($hash,"SOURCE");
    ESCVP21_QueueGet($hash,"PWR");
    ESCVP21_QueueGet($hash,"MSEL");
    ESCVP21_QueueGet($hash,"MUTE");
    ESCVP21_QueueGet($hash,"LAMP");
    ESCVP21_QueueGet($hash,"ERR");
    ESCVP21_QueueGet($hash,"SNO");
    ESCVP21_QueueGet($hash,"ASPECT");
    ESCVP21_QueueGet($hash,"LUMINANCE");

  } else {
    InternalTimer(gettimeofday()+5, "ESCVP21_GetStatus_t", "getStatus:".$name, 0);
  }
}

sub ESCVP21_GetStatus_t($)
{
  my($in) = shift;
  my(undef,$name) = split(':',$in);
  my $hash = $defs{$name};
  ESCVP21_GetStatus($hash);
}

sub ESCVP21_Set($@)
{
  my ($hash, $name, $cmd, @args) = @_;

  Log 5, "ESCVP21_Set: $cmd";

  my ($do_mute, $do_unmute) = (0,0);

  if($cmd eq 'mute') {
    if($#args == -1) {
      if(defined($hash->{READINGS}{MUTE})) {
	if($hash->{READINGS}{MUTE}{VAL} eq "OFF") {
	  $do_mute = 1;
	} else {
	  $do_unmute = 1;
	}
      } else {
	$do_mute = 1;
      }
    } else {
      if($args[0] eq 'on') {
	$do_mute = 1;
      } elsif($args[0] eq 'off') {
	$do_unmute = 1;
      }
    }
  } elsif($cmd eq 'on') {
    ESCVP21_Queue($hash,"powerOn");
    ESCVP21_QueueGet($hash,"PWR");
  } elsif($cmd eq 'off') {
    ESCVP21_Queue($hash,"powerOff");
    ESCVP21_QueueGet($hash,"PWR");
  } elsif($cmd eq 'raw') {
    ESCVP21_Queue($hash,join(" ", @args));
  } elsif($cmd eq 'input') {
    if($args[0] eq 'MUTE') {
      $do_mute = 1;
    } else {
      ESCVP21_ChangeSource($hash, $args[0]);
    }
  } elsif($cmd =~ /^([^-]+)-(.*)$/) {
    my ($on,$muted) = (0,0);
    ($on, $muted) = (1, 0) if $1 eq 'on';
    ($on, $muted) = (0, 0) if $1 eq 'off';
    ($on, $muted) = (1, 1) if $1 eq 'mute';

    if($on) {
      ESCVP21_Queue($hash,"powerOn");
      ESCVP21_QueueGet($hash,"PWR");

      ESCVP21_ChangeSource($hash, $2);

      if($muted) {
	$do_mute = 1;
      } else {
	$do_unmute = 1;
      }

    } else {
      ESCVP21_Queue($hash,"powerOff");
      ESCVP21_QueueGet($hash,"PWR");
    }

  } elsif($cmd eq '?') {
    my %table = %{$hash->{SourceTable}};
    my @inputs = ("MUTE",);
    push @inputs, $table{$_} foreach (sort keys %table);
    return "Unknown argument ?, choose one of on off mute input:" . join(",",@inputs);
  }
 
  if($do_mute) {
    ESCVP21_Queue($hash,"muteOn");
    ESCVP21_QueueGet($hash,"MUTE");
  } elsif($do_unmute) {
    ESCVP21_Queue($hash,"muteOff");
    ESCVP21_QueueGet($hash,"MUTE");
  }

}

sub ESCVP21_ChangeSource($$)
{
  my ($hash, $source) = @_;
  my %table = %{$hash->{SourceTable}};
  my $done = 0;
  while( my ($key, $value) = each %table ) {
    if( lc($source) eq lc($value) ) {
      ESCVP21_Queue($hash,"SOURCE " . uc($key));
      $done = 1;
      last;
    }
  }

  unless($done) {
    if($source =~ /([0-9a-f]{2})(-unknown)?/i) {
      ESCVP21_Queue($hash,"SOURCE " . uc($1));
      $done = 1;
    }
  }

  if($done) {
    ESCVP21_QueueGet($hash,"SOURCE");
    ESCVP21_QueueGet($hash,"MUTE");
  }
}

sub ESCVP21_QueueGet($$)
{
  my ($hash,$param) = @_;
  ESCVP21_Queue($hash,"get".$param);
}

sub ESCVP21_Queue($@)
{
  my ($hash,$cmd,$prepend) = @_;
  if($hash->{CommandQueue}) {
    if($prepend) {
      $hash->{CommandQueue} = $cmd . "|" . $hash->{CommandQueue};
    } else {
      $hash->{CommandQueue} .=  "|" . $cmd;
    }
  } else {
    $hash->{CommandQueue} = $cmd
  }
 
  ESCVP21_IssueQueuedCommand($hash);
  ESCVP21_ArmWatchdog($hash);
}


sub ESCVP21_IssueQueuedCommand($)
{
  my ($hash) = @_;
  # If a command is still active we can't do anything
  if($hash->{ActiveCommand}) {
    return;
  }
  return unless defined $hash->{CommandQueue};

  ($hash->{ActiveCommand}, $hash->{CommandQueue}) = split(/\|/, $hash->{CommandQueue}, 2);

  if($hash->{ActiveCommand}) {
    Log 4, "ESCVP21 executing ". $hash->{ActiveCommand};
    
    if($hash->{ActiveCommand} eq 'muteOn') {
      ESCVP21_Command($hash, "MUTE ON");
    } elsif($hash->{ActiveCommand} eq 'muteOff') {
      ESCVP21_Command($hash, "MUTE OFF");
    } elsif($hash->{ActiveCommand} eq 'powerOn') {
      ESCVP21_Command($hash, "PWR ON");
    } elsif($hash->{ActiveCommand} eq 'powerOff') {
      ESCVP21_Command($hash, "PWR OFF");
    } elsif($hash->{ActiveCommand} =~ /^get(.*)$/) {
      ESCVP21_Command($hash, $1."?");
    } else {
      # Assume a raw command and hope the user knows what he or she's doing
      ESCVP21_Command($hash, $hash->{ActiveCommand});
    }
  }

}

sub ESCVP21_UpdateState($)
{
  my ($hash) = @_;
  my $state = undef;
  my $onoff = 0;
  my $source = "unknown";
  my %table = %{$hash->{SourceTable}};

  if(defined($hash->{READINGS}{SOURCE})){
    $source = $hash->{READINGS}{SOURCE}{VAL} . "-unknown";
    while( my ($key, $value) = each %table ) {
      if( lc($hash->{READINGS}{SOURCE}{VAL}) eq lc($key) ) {
	$source = $value;
	last;
      }
    }
  }

  # If it's on or powering up, consider it on
  if($hash->{READINGS}{PWR}{VAL} eq '01' or $hash->{READINGS}{PWR}{VAL} eq '02') {
    if($hash->{READINGS}{MUTE}{VAL} eq 'ON') {
      $state = "mute";
    } else {
      $state = "on";
    }
    $onoff = 1;
    $state = $state . "-" . $source;
  } else {
    $state = "off";
    $onoff = 0;
  }

  readingsBulkUpdate($hash, "state", $state) unless $hash->{READINGS}{state}{VAL} eq $state;
  readingsBulkUpdate($hash, "onoff", $onoff) unless $hash->{READINGS}{onoff}{VAL} eq $onoff;
  readingsBulkUpdate($hash, "source", $source) unless $source eq "unknown" or $hash->{READINGS}{source}{VAL} eq $source;
}

sub ESCVP21_SourceTable($)
{
  my ($hash) = @_;
  my %table = ();
  my @available;
  my @override;

  foreach (@ESCVP21_SOURCES_AVAILABLE) {
    my ($modelre, $available_list) = @$_;
    if( $hash->{Model} =~ /^$modelre$/i ) {
      Log 4, "ESCVP21: Available sources defined by " . $modelre;
      @available = @$available_list;
      last;
    }
  }

  foreach (@ESCVP21_SOURCES_OVERRIDE) {
    my ($modelre, $override_list) = @$_;
    if( $hash->{Model} =~ /^$modelre$/i ) {
      Log 4, "ESCVP21: Override defined by " . $modelre;
      @override = @$override_list;
      last;
    }
  }
 
  foreach (@ESCVP21_SOURCES) {
    my ($code, $name) = @$_;
    if( (!@available) || ($code ~~ @available)) {
      $table{lc($code)} = lc($name);
      if(@override) {
	foreach (@override) {
	  my ($code_o, $name_o) = @$_;
	  if(lc($code_o) eq lc($code)) {
	    $table{lc($code)} = lc($name_o);
	  }
	}
      }
      Log 4, "ESCVP21: " . $code . " is mapped to " . $table{lc($code)};
    }
  }

  return %table;
}

sub ESCVP21_RemoteTable($)
{
  my ($hash) = @_;
  my %table = ();
  my @available;
  my @override;

  foreach (@ESCVP21_REMOTE_AVAILABLE) {
    my ($modelre, $available_list) = @$_;
    if( $hash->{Model} =~ /^$modelre$/i ) {
      Log 4, "ESCVP21: Available Remote keys defined by " . $modelre;
      @available = @$available_list;
      last;
    }
  }

  foreach (@ESCVP21_REMOTE_OVERRIDE) {
    my ($modelre, $override_list) = @$_;
    if( $hash->{Model} =~ /^$modelre$/i ) {
      Log 4, "ESCVP21: Override defined by " . $modelre;
      @override = @$override_list;
      last;
    }
  }
 
  foreach (@ESCVP21_REMOTE) {
    my ($code, $name) = @$_;
    if( (!@available) || ($code ~~ @available)) {
      $table{lc($code)} = lc($name);
      if(@override) {
	foreach (@override) {
	  my ($code_o, $name_o) = @$_;
	  if(lc($code_o) eq lc($code)) {
	    $table{lc($code)} = lc($name_o);
	  }
	}
      }
      Log 4, "ESCVP21: " . $code . " is mapped to " . $table{lc($code)};
    }
  }

  return %table;
}


sub ESCVP21_Command($$)
{
  my ($hash,$command) = @_;
  DevIo_SimpleWrite($hash,$command."\x0d",'');
}

1;

=pod
=begin html

<a name="ESCVP21"></a>
<h3>ESCVP21</h3>
<ul>

  Many EPSON projectors (both home and business) have a communications interface
  for remote control and status reporting. This can be in the form of a serial
  port (RS-232), a USB port or an Ethernet port. The protocol used on this port
  most often is ESC/VP21. This module supports control of simple functions on the
  projector through ESC/VP21. It has only been tested with EH-TW3000 over RS-232.
  The network protocol is similar and may be supported in the future.

  <a name="ESCVP21define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ESCVP21 &lt;device&gt; [&lt;model&gt; [&lt;timer&gt;]]</code> <br>
    <br>
    USB or serial devices-connected devices:<br><ul>
      &lt;device&gt; specifies the serial port to communicate with the projector.
      The name of the serial-device depends on your distribution and several
      other factors. Under Linux it's usually something like /dev/ttyS0 for a
      physical COM port in the computer, /dev/ttyUSB0 or /dev/ttyACM0 for USB
      connected devices (both USB projector or serial projector using USB-serial
      converter). The numbers may differ, check your kernel log (using the dmesg
      command) soon after connecting the USB cable. Many distributions also offer
      a consistent naming in /dev/serial/by-id/, check there.<br><br>

      You can also specify a baudrate if the device name contains the @
      character, e.g.: /dev/ttyACM0@9600, though this should usually always
      be 9600.<br><br>

      If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the
      perl module Device::SerialPort is not needed, and fhem opens the device
      with simple file io. This might work if the operating system uses sane
      defaults for the serial parameters, e.g. some Linux distributions and
      OSX.  <br><br>

    </ul>
    Network-connected devices:<br><ul>
    Not supported currently.
    </ul>
    <br>

    If a model name is specified (case insensitive, without the "emp-" or "eh-"
    prefix), it is used to limit the possible input source values to the ones
    supported by the projector (if known) and may be used to map certain source
    values to better symbolic names. If the model name isn't specified it defaults
    to "unknown".

    The projector must be queried for readings changes, and the time between
    queries in seconds is specified by the optional timer argument. If it isn't
    specified it defaults to 30.

    Examples:
    <ul>
      <code>define Projector_Living_Room ESCVP21 /dev/serial/by-id/usb-Prolific_Technology_Inc._USB-Serial_Controller_D-if00-port0 tw3000</code><br>
    </ul>


  </ul>
  <br>

  <a name="ESCVP21set"></a>
  <b>Set </b>
  <ul>
    <li>on<br>
	Switch the projector on.
	</li><br>
    <li>off<br>
	Switch the projector off.
	</li><br>
    <li>mute [on|off]<br>
	'Mute' the projector output, e.g. display a black screen.
	If no argument is given, the mute state will be toggled.
	</li><br>
    <li>input &lt;source&gt;.<br>
	Switch the projector input source. The names are the same as
	reported by the 'source' reading, so if in doubt look there.
	A raw two character hex code may also be specified.
	</li><br>
    <li>&lt;state&gt;-&lt;source&gt;<br>
	Switch state ("on", "off" or "mute") and source in one command.
	The source is ignored if the new state is off.
	</li><br>

  </ul>

  <a name="ESCVP21get"></a>
  <b>Get</b>
  <ul>N/A</ul>

  <a name="ESCVP21attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html
=begin html_DE

<a name="ESCVP21"></a>
<h3>ESCVP21</h3>
<ul>

  Viele EPSON-Projektoren sind mit einem Anschluss f&uuml;r die Fernbedienung von einem
  Computer ausgestattet. Das ist entweder ein serieller Anschluss (RS-232), ein
  USB-Anschluss, oder ein Ethernet-Anschluss. Das verwendete Protokoll ist h&auml;ufig
  ESC/VP21. Dieses Modul unterst&uuml;tzt grundlegende Steuerungsfunktionen des Projektors
  &uuml;ber ESC/VP21 f&uuml;r Projektoren mit USB- (ungestet) und RS/232-Anschluss. Das
  Netzwerkprotokoll ist &auml;hnlich und k&ouml;nnte evt. in der Zukunft unterst&uuml;tzt werden.

  <a name="ESCVP21define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ESCVP21 &lt;device&gt; [&lt;model&gt; [&lt;timer&gt;]]</code> <br>
    <br>
    Per USB oder seriell angeschlossene Ger&auml;te:<br><ul>
      &lt;device&gt; gibt den seriellen Port an, an dem der Projektor angeschlossen
      ist. Der Name des Ports h&auml;ngt vom Betriebssystem bzw. der Distribution un
      anderen Faktoren ab. Unter Linux ist es h&auml;ufig etwas &auml;hnliches wie /dev/ttyS0
      bei einem fest installierten seriellen Anschluss, oder /dev/ttyUSB0 oder
      /dev/ttyACM0 bei einem per USB angeschlossenem Ger&auml;t (entweder der Projektor
      &uuml;ber USB, oder ein serieller Projektor mit einem USB-RS-232-Wandler). Die
      Zahl kann abweichen, genaue Angaben sollten im Kernel-Log zu finden sein (mit
      dem dmesg-Befehl anzusehen), nachdem das USB-Kabel verbunden wurde. Viele
      Distributionen bieten ausserdem ein konsistentes Namensschema (&uuml;ber symlinks)
      in /dev/serial/by-id/ an.<br><br>
     
      Zus&auml;tzlich kann eine Baudrate angegeben werden, durch Verwendung des @-Zeichens
      in der device-Angabe, z.B. /dev/ttyACM0@9600. Das sollte allerdings eigentlich
      immer 9600 sein.<br><br>

      Wenn die Baudrate als "directio" angegeben wird (z.B. /dev/ttyACM0@directio),
      dann wird das Perl-Modul Device::SerialPort nicht ben&ouml;tigt und fhem spricht
      das Ger&auml;t mit einfacher Datei-I/O an. Das kann funktionieren, wenn das
      Betriebssystem sinnvolle Standardwerte f&uuml;r die seriellen Parameter verwendet,
      z.B. unter einigen Linux-Distributionen und OSX.<br><br>

    </ul>
    Per Netzwerk angeschlossene Ger&auml;te:<br><ul>
    Zur Zeit nicht unterst&uuml;tzt
    </ul>
    <br>

    Wenn der Modellname angegeben wird (majuskelignorant, ohne das Pr&auml;fix "emp-"
    oder "eh-"), wird er benutzt, um die Liste der Eing&auml;nge auf die tats&auml;chlich
    vorhandenen zu reduzieren (falls bekannt) und unter Umst&auml;nden auch, um manche
    Eing&auml;nge auf bessere Namen umzubenennen. Wenn das Projektormodell nicht
    angegeben wird, wird standardm&auml;&szlig;ig "unknown" angenommen.<br><br>


    Der Projektor wird von einem internen Timer regelm&auml;&szlig;ig nach Status&auml;nderungen
    gepollt. Die Zeit zwischen zwei Abfragen, in Sekunden, wird mit dem optionalen
    timer-Argument angegeben. Wenn es nicht spezifiziert wird, wird standardm&auml;&szlig;ig
    30 angenommen.<br><br>

    Beispiele:
    <ul>
      <code>define Beamer_Wohnzimmer ESCVP21 /dev/serial/by-id/usb-Prolific_Technology_Inc._USB-Serial_Controller_D-if00-port0 tw3000</code><br>
    </ul>


  </ul>
  <br>

  <a name="ESCVP21set"></a>
  <b>Set </b>
  <ul>
    <li>on1<br>
	Schaltet den Projektor an.
	</li><br>
    <li>off<br>
	Schaltet den Projektor aus.
	</li><br>
    <li>mute [on|off]<br>
	Abschalten der Ausgabe, also zum Beispiel durch Anzeigen eines
	schwarzen Bildschirms.
	Wenn kein Argument angegeben wird, wird der Abschaltungszustand
	invertiert.
	</li><br>
    <li>input &lt;source&gt;.<br>
	&Auml;ndern des Projektoreingangs. Die Namen stammen aus der Dokumentation
	und sind dieselben die im "source"-Reading ausgegeben werden.
	Der Eingang kann auch direkt als zwei-Zeichen Hexcode angegeben werden.
	</li><br>
    <li>&lt;state&gt;-&lt;source&gt;<br>
	&Auml;ndert den Projektorzustand ("on", "off", oder "mute") und den
	gew&auml;hlten Eingang in einem einzigen Kommando. Der Eingang wird
	ignoriert, wenn der neue Zustand "off" ist.
	</li><br>

  </ul>

  <a name="ESCVP21get"></a>
  <b>Get</b>
  <ul>N/A</ul>

  <a name="ESCVP21attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html_DE
=cut
