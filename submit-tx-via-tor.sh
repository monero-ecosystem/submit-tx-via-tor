#!/bin/bash
 
SCRIPT_DESCRIPTION="\
This is a simple script designed to make it very hard for third parties to link
your monero transactions to you via your IP address. This script achieves this
extra privacy by sending your monero transaction to the monero network via the
Tor network.
 
How it works is simple: you pass a raw_monero_tx file (a monero transaction
created by monero-wallet-cli) to this script as an argument and it will
submit this transaction to a monerod, tor onion node via the Tor network. Your
real IP address will be concealed from the remote monerod. The real IP address
of the remote monerod will be concealed from you. Any computers passively
monitoring your connection will not be able to tell which computer you are
connecting to and what data you're sending.
 
To make monero-wallet-cli (the most popular Monero wallet) create a
raw_monero_tx file instead of submitting a transaction directly to the
monero network via your Internet connection, you have to start
monero-wallet-cli with the --do-not-relay switch or add do-not-relay=1
to your monero-wallet-cli configuration file.
 
Make sure you have installed Tor before attempting to use this script.
 
https://www.torproject.org/
 
If you use the default tor settings, this script should connect to your local
tor node without issue.
 
You should inspect and if necessary edit the USER CONFIG variables in this
script before using it."
 
 
 
###############################################################################
# USER CONFIG: GENERAL
 
# The following path will be checked if you don't specify the path to a
# raw_monero_tx file as a argument when calling this script.
FALLBACK_RAW_MONERO_TX_PATH="${HOME}/raw_monero_tx"
 
# Specify the Tor node socks server address.
# Tor's default value is: 127.0.0.1:9050
# Consult your torrc file to find out what it actually is.
# The value should be of the form: [user:password@]proxyhost:port
TOR_NODE='127.0.0.1:9050'
 
 
###############################################################################
# USER CONFIG: NODE SELECTION
 
# Uncomment only one NODE variable
 
# XMRlab node:
#
# Announcement:
#   https://www.reddit.com/r/Monero/comments/78cqsd/xmrlab_starts_a_free_public_monero_node_as_onion/
# Node home page:
#   http://xmrag4hf5xlabmob.onion/
#NODE='xmrag4hf5xlabmob.onion:18081'
 
# MoneroWorld.com node:
#
# Node home page:
#   https://moneroworld.com/
# Special note:
#   This is actually the onion address of a proxy server which will
#   automatically route your connect to one of many online monero daemons.
NODE='zdhkwneu7lfaum2p.onion:18099'
 
###############################################################################
 
 
final_report() {
    echo '____________________________________'
    echo
    if [[ $1 -eq 0 ]]; then
        echo ' SUCCESSFULLY SUBMITTED TRANSACTION'
    else
        echo ' FAILED TO SUBMIT A TRANSACTION'
    fi
    echo '____________________________________'
    echo
    exit $1
}
 
echo 'Checking script dependencies are installed.'
command -v curl &>/dev/null
if [[ $? -ne 0 ]]; then
    echo "ERROR: curl is not installed."
    echo "       On many systems you can install it by entering into a terminal:"
    echo "       apt-get install curl"
    exit 1
fi
 
# Check for an option argument.
 
if [[ "$1" == -* ]]; then
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "$0 [PATH_TO_RAW_MONERO_TX]"
        echo
        echo "$SCRIPT_DESCRIPTION"
        exit 0
    elif [[ "$1" == "--test" || "$1" == "-t" ]]; then
        echo 'Testing connection to the configured remote monerod:'
        echo "$NODE"
        OUTPUT="$(
           /usr/bin/curl \
               --proxy socks5h://"$TOR_NODE" \
               --request POST "${NODE}/json_rpc" \
               --data '{"jsonrpc":"2.0","id":"0","method":"getblockcount"}' \
               --header 'Content-Type: application/json'
       )"
        echo "$OUTPUT" | grep -qF '"status": "OK"'
        if [[ $? -eq 0 ]]; then
            echo "$OUTPUT"
            echo
            echo "Successfully connected to remote note."
            echo "Everything seems to be working."
            exit 0
        else
            echo "$OUTPUT"
            echo
            echo "Failed to connect to the remote note."
            echo "Make sure Tor is running and configured properly."
            echo "You could also try a different NODE entry in this script."
            exit 1
        fi
    else
        echo "ERROR: unknown argument: $1"
        final_report 1
    fi
fi
 
echo 'Checking the raw_monero_tx file is present.'
if [[ "$1" != "" ]]; then
    RAW_MONERO_TX="$1"
elif [[ "$FALLBACK_RAW_MONERO_TX_PATH" != "" ]]; then
    RAW_MONERO_TX="$FALLBACK_RAW_MONERO_TX_PATH"
else
    echo "ERROR: No raw_monero_tx file was given as a command line argument"
    echo "       and no fallback location to check is specified in the script."
    echo "       Run script with --help argument for some hints on what to do."
    final_report 1
fi
if [[ ! -f "$RAW_MONERO_TX" ]]; then
    echo "ERROR: A monero transaction file was not found at the following path:"
    echo "       $RAW_MONERO_TX"
    echo "       Run script with --help argument for some hints on what to do."
    final_report 1
fi
 
echo 'Loading the file.'
readonly TX="$(cat "$RAW_MONERO_TX")"
 
echo 'Checking the file is a valid raw, monero tx.'
readonly TX_MIN_LEN=3000 # Assume minimum is above 1500 Bytes. x2 because hex-ascii encoding.
readonly TX_LEN=${#TX}
if (( TX_LEN < TX_MIN_LEN )); then
    echo "ERROR: the raw monero tx file is less than $TX_MIN_LEN characters"
    echo "       long. Something is probably wrong with it."
    final_report 1
fi
# TODO: check the file is no bigger or smaller than the max and min size of a transaction as per protocol defined limits.
# TODO: check that the file only contains ASCII symbols a-f and 0-9.
# TODO: check for common magic bytes present in all valid transactions.
 
echo 'Constructing the JSON-RPC message.'
DATA="{\"tx_as_hex\":\"${TX}\", \"do_not_relay\":false}"
 
echo 'Submitting tx to the remote monerod.'
OUTPUT="$(
   curl \
       --proxy socks5h://"$TOR_NODE" \
       --request POST "${NODE}/sendrawtransaction" \
       --data "$DATA" \
       --header 'Content-Type: application/json' \
       --max-time 300 \
       --max-filesize 9999 \
       --max-redirs 0
)"
echo "The remote node returned:"
# TODO: is it dangerous to echo a string controlled by an untrusted source?
echo "$OUTPUT"
echo "$OUTPUT" | grep -qF '"status": "OK"'
if [[ $? -eq 0 ]]; then
    final_report 0
else
    echo "ERROR: Failed to submit raw tx to the following remote node:"
    echo "       $NODE"
    echo "       You could try a different NODE entry in this script."
    final_report 1
fi
