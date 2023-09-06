#!/bin/bash

function setupDnsEntry() {
  mode=$(readConfig ".dns.record" "manual")
  eventStage "DnsEntryProcess_$mode"
}

function setupManualDnsEntry() {
    # TODO: Ensure DNS is resolvable
    return
}

event on preSetup setupDnsEntry
event on onDnsEntryProcess_manual setupManualDnsEntry