# uim toolbar for perl tkx

use strict;
use warnings;
use Tkx;
use POSIX qw(pipe fork dup2 STDOUT_FILENO STDIN_FILENO);
use IO::Socket::UNIX;


################################################################
## global variables

# stores prop_list_update message information
my %props = ();

# main window
my $top = undef;

################################################################
## subroutines

## set toplevel window to sticky
sub sticky_window {
	my $top = shift;
	Tkx::wm_withdraw($top);
	my $wid = Tkx::winfo_id($top);

	# get parent window id
	my $str = qx(xwininfo -tree -id $wid);
	$str =~ /Parent window id: *([x[:xdigit:]]*)/i;
	my $pwid = $1;

	system("xprop -id $pwid -format _NET_WM_DESKTOP 32c -set _NET_WM_DESKTOP 0xFFFFFFFF");
	Tkx::wm_deiconify($top);
}

## return socket client
sub uim_helper {
	my $client;
	my $socket_path;
	if ($ENV{XDG_RUNTIME_DIR}) {
		$socket_path = "$ENV{XDG_RUNTIME_DIR}/uim/socket/uim-helper",
		  $client = IO::Socket::UNIX->new(Type => SOCK_STREAM(),
		                                  Peer => $socket_path,
		                                 );
	}
	if (!$client) {
		$socket_path = "$ENV{HOME}/.uim.d/socket/uim-helper";
		$client = IO::Socket::UNIX->new(Type => SOCK_STREAM(),
		                                Peer => $socket_path,
		                               );
	}
	return $client;
}

sub read_cb {
	my $chan = shift;
	my $buf = Tkx::read($chan);

	if (!$buf) {
		return;
	}

	my @lines = split("\n", $buf);

	## parse
	## prop_list_update: delete all comboboxes
	## branch: create combobox
	## leaf: add item to combobox
	my $combo = undef;
	for my $line (@lines) {
		#print STDERR "$line\n";
		my @fileds = split /\t/, $line;

		if ($line =~ /^prop_list_update/) {
			Tkx::destroy(keys %props);
			$combo = undef;
			%props = ();
		}

		if ($line =~ /^branch/) {
			$combo = $top->new_ttk__combobox(-state => 'readonly');
			$combo->set($fileds[3]); # branch's label string
			$combo->g_pack(-side => 'left');
			$combo->g_bind('<<ComboboxSelected>>' =>
			               [sub {
				                my $w = shift;
				                my $act = ${$props{$w}[$w->current]}[5]; # leaf's action id
				                # send action
				                Tkx::after(100, sub {send_message("prop_activate\n${act}\n\n")});
			                }, $combo]); # pass to subroutine combobox widget path
		}

		if ($combo && $line =~ /^leaf/) {
			# append to props. $combo used as hash-key
			$props{$combo}[scalar @{$props{$combo}}] = \@fileds;

			# append combobox item
			my $v = $combo->cget('-values') . " " . Tkx::list($fileds[3]); # leaf's label string
			$combo->configure(-values => $v);
		}
	}
}

# send message to uim-helper
sub send_message {
	my $msg = shift;

	my $client = uim_helper();
	if ($client) {
		print $client "$msg\n\n";
		close($client);
	} else {
		print STDERR "send_message:error\n";
	}
}

################################################################
## program start

# child-stdout -> parent-stdin
my @c2p = POSIX::pipe();
my $pid = POSIX::fork();
if ($pid == 0) {
	# child
	POSIX::close($c2p[0]);
	POSIX::dup2($c2p[1], STDOUT_FILENO);
	POSIX::close($c2p[1]);

	# watch socket
	my $client = undef;
	while (1) {
		while (!($client = uim_helper())) {
			print STDERR "can not connect to uim-helper\n";
			sleep 5;
		}
		while (my $msg = <$client>) {
			if (!(print $msg)) {
				# parent was terminated?
				close($client);
				exit;
			}
		}
	}
	exit;
} elsif ($pid > 0) {
	# parent
	POSIX::dup2($c2p[0], STDIN_FILENO);
	POSIX::close($c2p[0]);
	POSIX::close($c2p[1]);

	# watch stdin (uim-helper)
	Tkx::fconfigure('stdin', -blocking => 0);
	Tkx::fileevent('stdin', 'readable', [ \&read_cb, 'stdin' ]);
} else {
	# fork error
	exit 1;
}

# main window
$top = Tkx::widget->new('.');
$top->g_wm_focusmodel('active');
Tkx::tk_useinputmethods(0);
Tkx::after(1000, [\&sticky_window, $top]);

## get prop list information
Tkx::after(100, [\&send_message, "prop_list_get\n\n"]);

Tkx::MainLoop;

# kill child
kill('HUP', $pid);
