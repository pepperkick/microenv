#!/bin/bash

function setupDnsEntry() {
  if [[ "$(readConfig ".dns.enabled" "true")" == "false" ]]; then
    return
  fi

  mode=$(readConfig ".dns.record" "manual")
  eventStage "DnsEntryProcess_$mode"
}

function setupManualDnsEntry() {
    # TODO: Ensure DNS is resolvable
    return
}

event on preSetup setupDnsEntry
event on onDnsEntryProcess_manual setupManualDnsEntry