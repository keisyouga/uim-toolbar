#!/usr/bin/perl
# uim toolbar using perl tkx

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

# frame, it contain menubuttons
my $frame = undef;

################################################################
## subroutines

# ## set toplevel window to sticky
# sub sticky_window {
# 	my $top = shift;
# 	Tkx::wm_withdraw($top);
# 	my $wid = Tkx::winfo_id($top);

# 	# get parent window id
# 	my $str = qx(xwininfo -tree -id $wid);
# 	$str =~ /Parent window id: *([x[:xdigit:]]*)/i;
# 	my $pwid = $1;

# 	system("xprop -id $pwid -format _NET_WM_DESKTOP 32c -set _NET_WM_DESKTOP 0xFFFFFFFF");
# 	Tkx::wm_deiconify($top);
# }

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

## menubutton action
sub menu_command {
	my $id = shift;           # indication_id
	my $act = $props{$id}[5]; # leaf's action id
	# send action
	Tkx::after(100, sub {send_message("prop_activate\n${act}\n\n")});
}

sub read_cb {
	my $chan = shift;
	my $buf = Tkx::read($chan);

	if (!$buf) {
		return;
	}

	my @lines = split("\n", $buf);

	## parse
	## prop_list_update: delete all menubuttons
	## branch: create menubutton widget, menu widget
	## leaf: add item to menu
	my $menu = undef;
	my $menubutton = undef;
	for my $line (@lines) {
		#print STDERR "$line\n";
		my @fields = split /\t/, $line;

		if ($line =~ /^prop_list_update/) {
			# destroy all menubuttons
			Tkx::destroy(Tkx::SplitList($frame->g_winfo_children()));

			# clear %props
			%props = ();
		}

		if ($line =~ /^branch/) {
			# menu must be child of menubutton, so create menubutton first
			$menubutton = $frame->new_menubutton(-direction => 'right', -relief => 'raised');
			$menu = $menubutton->new_menu(-tearoff => 0);
			$menubutton->configure(-menu => $menu);
			$menubutton->g_pack(-side => 'left');
		}

		if ($line =~ /^leaf/) {
			if ($menubutton && $menu) {
				# append \@fields to props
				my $id = $fields[1]; # indication_id
				$props{$id} = \@fields;

				# append menu item
				my $str = $fields[3]; # menu label
				# selected item
				if ($line =~ /\*$/) {
					$menubutton->configure(-text => $fields[2]);
					$str = $str . '*';
				}
				$menu->add_command(-label => $str, -command => [\&menu_command, $id]);
			}
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

my $mw = Tkx::widget->new('.');
$mw->g_wm_withdraw();
$top = $mw->new_toplevel();
$frame = $top->new_frame(-borderwidth => 5);
$frame->g_pack(-side => 'left');
$top->new_button(-text => 'exit', -padx => 0, -command => sub {$mw->g_destroy();}
                )->g_pack(-side => 'right');
Tkx::tk_useinputmethods(0);

# overrideredirect & drag-move
$top->g_bind('<ButtonPress-1>' => [sub {
	my $winpx = shift;
	my $winpy = shift;
	$top->g_bind('<B1-Motion>' => [sub {
		my $w = shift;
		my $rootpx = Tkx::winfo_pointerx($w);
		my $rootpy = Tkx::winfo_pointery($w);
		$top->g_wm_geometry(sprintf("+%i+%i", $rootpx - $winpx, $rootpy - $winpy));
	                               }, Tkx::Ev('%W')]);
                                   }, Tkx::Ev('%x', '%y')]);
$top->g_wm_overrideredirect(1);

#Tkx::after(1000, [\&sticky_window, $top]);

## get prop list information
Tkx::after(100, [\&send_message, "prop_list_get\n\n"]);

Tkx::MainLoop;

# kill child
kill('HUP', $pid);
