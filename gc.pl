# $Id: gc.pl,v 1.5 2003/09/24 00:22:50 gonzo Exp $

# 
# This project use code from ChatBot jabber client
# Author of ChatBot is reatmon <reatmon@jabber.org>

use strict;
use vars qw($VERSION %IRSSI);

use Irssi;
use Net::Jabber qw( Client );
use XML::Stream qw( Tree );
use POSIX;
use Encode;

$VERSION = '0.1.2';
%IRSSI = (
    authors     => 'Oleksnadr Tymoshenko',
    contact     => "gonzo\@bluezbox.com",
    name        => 'Jabber groupchat Irssi plugin',
    description => 'This script adds  groupchat functionality for Irssi',
    license     => 'BSD',
);

# global variables
our $CHARSET = "latin1";
our ($Connection, $MainWindow, $Timeout);
our (%rooms, %buddies, %presences);

use constant RESOURCE  => 'IrssiPlugin';
use constant PORT      => 5222;          # Port to connect to
use constant PORT_SSL  => 5223;          # SSL port to connect to

Irssi::command_bind (jconnect => \&jconnect);
Irssi::command_bind (jwho => \&jwho);
Irssi::command_bind (jjoin => \&jjoin);
Irssi::command_bind (jmsg => \&jmsg);
Irssi::command_bind (jchat => \&jchat);
Irssi::command_bind (jpart => \&jpart);
Irssi::signal_add_first('send text', "event_send_text");

# recognize language by LC_CTYPE
# may be it is wrong but it works in most cases
my $locale = setlocale(LC_CTYPE);
$locale =~ /[a-z]+_[a-z]+\.(.*)/i;
$CHARSET = lc($1) if(defined $1);

#
# SYNTAX: /jmsg jid message
#
sub jmsg {
    if(!$Connection) {
        Irssi::print("Not connected") ;
        return;
    }
    my ($data, $server, $witem) = @_;
    $data =~ /\s*(\S+)\s+(.*)$/;
    my ($jid, $msg) = ($1, $2);
    message($jid, $msg);
    $MainWindow->print("\00311Message to $jid\00306 $msg",MSGLEVEL_MSGS);
}

#
# SYNTAX: /jchat jid [message]
#
sub jchat {
    if(!$Connection) {
        Irssi::print("Not connected") ;
        return;
    }
    my ($data, $server, $witem) = @_;
    $data =~ /\s*(\S+)\s+(.*)$/;
    my ($jid, $msg) = ($1, $2);
    my $window = open_chat_window($jid);
    $window->print("\00309<me>\00307 $msg",MSGLEVEL_MSGS);
    message($jid, $msg);
}

#
# SYNTAX: /jpart 
#
sub jpart {

    if(!$Connection) {
        Irssi::print("Not connected") ;
        return;
    }

    my ($data, $server, $witem) = @_;
    $data =~ /\s*(\S+)\s+(.*)$/;
    my ($jid, $msg) = ($1, $2);
    $jid = GetJIDofActiveWindow();
    return unless $jid;

    if(exists($rooms{$jid})) {
        $Connection->PresenceSend(to=>$jid, type=>"unavailable");
        delete($rooms{$jid})
    } 
    else {
        delete($buddies{$jid})
    }

    my $window = Irssi::active_win();
    $window->destroy();
}

#
# SYNTAX: /jjoin room nick server
#
sub jjoin {

    if(!$Connection) {
        Irssi::print("Not connected");
        return;
    }

    my ($data, $server, $witem) = @_;
    my ($room, $nick, $cserver) = split /\s+/, $data;
    my $jid = new Net::Jabber::JID();
    my $window = Irssi::Windowitem::window_create($room,1);
    $window->set_name("$room\@$cserver");
    $jid->SetUserID($room);
    $jid->SetServer($cserver);
    $jid->SetResource($nick);
    $rooms{$jid->GetJID()}->{jid} = $jid;
    $rooms{$jid->GetJID()}->{window} = $window;
    $Connection->PresenceSend(to=>$jid);
    $window->set_active();
}

#
# SYNTAX: /jwho
# Show the list of people
#
sub jwho
{
    if(!$Connection) {
        Irssi::print("Not connected");
        return;
    }

    my $jid = GetJIDofActiveWindow();
    my $window = Irssi::active_win() ? Irssi::active_win()->{active} 
        : undef;
    return unless (defined($jid));
    return unless (defined($window));

    foreach my $user (keys %{$presences{$jid}}) {
        my $status = $presences{$jid}->{$user};
        $user =~ s/$jid\///;
        $window->print("\00310$user \00307 [$status]",MSGLEVEL_MSGS) 
            if (defined($status));
    }
    
}


sub event_send_text {
    my ($body, $server, $witem) = @_;
    my $jid = GetJIDofActiveWindow();
    return unless $jid;
    if(exists($rooms{$jid})) {
        chat_message($jid, $body);
    }
    else {
        message($jid, $body);
        my $window = Irssi::active_win();
        $window->print("\00309<me>\00307 $body",MSGLEVEL_MSGS);
    }
}

sub jconnect {
    my ($data, $foo, $witem) = @_;
    my @opts = split(/\s+/, $data);
    my $use_ssl = 0;
    my $port = PORT;

    if (grep { /^-ssl$/i } @opts) {
        $use_ssl = 1;
        @opts = grep {!/^-ssl$/i} @opts;
    }

    if (grep { /^-port$/i } @opts) {
        for (my $i = 0; $i < @opts; $i++) {
            if ($opts[$i] =~ /^-port$/) {
                # splice returns last element removed
                $port = splice @opts, $i, 2;
            }
        }
    }
    elsif ($use_ssl) {
        $port = PORT_SSL;
    }

    my ($server, $user, $password) = @opts;
    if(!defined($MainWindow))
    {
        $MainWindow = Irssi::Windowitem::window_create("jabber",1);
    }
    $MainWindow->set_active();
    # Create a new Jabber client and connect
    # --------------------------------------
    $Connection = Net::Jabber::Client->new();
    $MainWindow->print("Connecting to $server:$port as $user SSL:$use_ssl", 
        MSGLEVEL_MSGS);
    $Connection->Connect( "hostname" => $server,
                          "port"   => $port,
                          "ssl" => $use_ssl )
        or die "Cannot connect ($!)\n";
    $MainWindow->print("Connected.",MSGLEVEL_JOINS );
    # Identify and authenticate with the server
    # -----------------------------------------
    my @result = $Connection->AuthSend( "username" => $user,
                                    "password" => $password,
                                    "resource" => RESOURCE );
    if ($result[0] ne "ok") {
      die "Ident/Auth with server failed: $result[0] - $result[1]\n";
    }
    $MainWindow->print("Logged in",MSGLEVEL_JOINS );

    $Connection->PresenceSend();
    $MainWindow->print("Presence sent",MSGLEVEL_JOINS );

    $Connection->SetCallBacks( 
                message => \&messageCB,
                presence=>\&presenceCB
    );

    $Timeout = Irssi::timeout_add(3000, \&process, "");
    $MainWindow->print("Initalized");
}

sub process
{
    if(! (defined $Connection->Process(1))) {
        $MainWindow->print("Disconnected...") if($MainWindow);
        $Connection = undef;
        ($Timeout) && Irssi::timeout_remove($Timeout);
    }
}



#
# Message callback
#

sub messageCB
{
    my $sid = shift;
    my $message = shift;

    #-------------------------------------------------------------------------
    # Don't even look at the history messages.  Let the past fade away.
    #-------------------------------------------------------------------------
    my @xTags = $message->GetX("jabber:x:delay");
    return if ($#xTags > -1);

    my $fromJID = $message->GetFrom("jid");


    #-------------------------------------------------------------------------
    # If this is a normal message then trigger the event.  We really don't like
    # these... but someone aske for them, so we will provide them but put in a
    # configuration option to turn them off by default. =)
    #-------------------------------------------------------------------------

    #---------------------------------------------------------------------------
    # If this is a groupchat message then trigger the event, and note the
    # activity
    #---------------------------------------------------------------------------
    if ($message->GetType() eq "groupchat") {
        my $from = $message->GetFrom("");
        my $window = $rooms{$fromJID->GetJID()}->{window};
        $from = encode($CHARSET, $from);
        $from =~ /\/(.*)$/s;
        my $nick = $1;
        my $body = $message->GetBody();
        $body = encode($CHARSET, $body);
        return unless $window;
        if($nick eq '') {
            $window->print("$body",MSGLEVEL_JOINS );
        }
        else {
            if($body =~ /\s*\/me\s*(.*)$/i) {
                $window->print("* \00311$nick\00307 $1",MSGLEVEL_MSGS);
            }
            else {
                $window->print("\00309<$nick>\00307 $body",MSGLEVEL_MSGS);
            }
        }
    }

    if (($message->GetType() eq "chat") || ($message->GetType() eq "normal")) {
        my $window;
        if(defined($buddies{$fromJID->GetJID()})) {
            $window = $buddies{$fromJID->GetJID()};
        }
        else {
            $window = open_chat_window($fromJID->GetJID());
        }

        my $from = $message->GetFrom("");
        $from = encode($CHARSET, $from);
        my $body = $message->GetBody();
        $body = encode($CHARSET, $body);
        return unless $window;

        if($body =~ /\s*\/me\s*(.*)$/i) {
            $window->print("* \00311$from\00307 $1",MSGLEVEL_MSGS);
        }
        else {
            $window->print("\00309<$from>\00307 $body",MSGLEVEL_MSGS);
        }
    }
}

#
# Presence callback
#

sub presenceCB
{
    my $sid = shift;
    my $presence = shift;

    my $fromJID = $presence->GetFrom("jid");
    my $from = encode($CHARSET, $presence->GetFrom(""));
    my $fromID = $fromJID->GetResource();
    my $status = encode($CHARSET, $presence->GetStatus()) || "online";
    return if !exists($rooms{$fromJID->GetJID()});

    #---------------------------------------------------------------------------
    # Exit if this did not come from one of the channels are logged into.
    # This cuts down on the amount of processing required by ChatBot.
    #---------------------------------------------------------------------------
    my $window = $rooms{$fromJID->GetJID()}->{window};
    return unless(defined($window));

    $from =~ /\/(.*)$/s;
    my $nick = $1;

    if($presence->GetType() eq  "unavailable") {
        delete($presences{$fromJID->GetJID()}->{$from});
        $window->print("\00308*\00303 $nick \00307 disconnected",MSGLEVEL_MSGS);
        $status = "offline";
        return;
    }

    $window->print("\00308*\00303 $nick \00307 -> $status",MSGLEVEL_MSGS);
    $presences{$fromJID->GetJID()} = () unless $presences{$fromJID->GetJID()};
    $presences{$fromJID->GetJID()}->{$from} = $status;
}

##
#  Message routines
##

sub chat_message
{
    my ($jid, $body) = @_;
    # decode to string with utf8 flag set
    $body = decode( $CHARSET, $body );
    my $message = new Net::Jabber::Message();
    $message->SetMessage(to=>$jid);
    $message->SetMessage(type=>"groupchat",
                        body=> $body );
    $Connection->Send($message);
}

sub message
{
    my ($jid, $body) = @_;
    # decode to string with utf8 flag set
    $body = decode( $CHARSET, $body );
    my $message = new Net::Jabber::Message();
    $message->SetMessage(to=>$jid);
    $message->SetMessage(type=>"chat",
                        body=> $body );
    $Connection->Send($message);
}


sub GetJIDofActiveWindow
{
    my $window = Irssi::active_win();
    return undef unless $window;
    return GetJIDbyWindow($window);
}

sub GetJIDbyWindow
{
    my $window = shift;
    return $window->{name} if(defined($window->{name}));
    return undef;
}

sub open_chat_window
{
    my ($jid) = @_;
    my $window = Irssi::Windowitem::window_create($jid,1);
    $window->set_name($jid);
    $buddies{$jid} = $window;
    $window->set_active();
    return $window;
}
