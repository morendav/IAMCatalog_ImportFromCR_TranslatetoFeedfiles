# IAMCatalog_ImportFromCR_TranslatetoFeedfiles

Read from a ticketing system export (txt file).
Translate text file to a number of flat feed file for our IAM system utilities
Secure connect to Oracle SQL and pull relevant keys

## Description

This project aimed to automate various mechanical tasks for a fulfillment team.
Problem Statement:  On average there will be ~100 service requests to create OpenStack tenants spaces er month. these requests will be generated in the ticketing system via a direct API call, in order to fulfill these requests the fulfillment team would need to take several datapoints, correlate them to existing IAM data (e.g. user login <--> user key, user name, etc) and produce a handful of feedfiles that our secure IAM enterprise solution could then intake and create representations of the new endpoint tenant in our IAM system.

In order to deliver on each request, the fulfillment team would need to (1) enrich the existing unrefined entitlments with data from the CR, (2) create n number of role based provisioning buckets per CR, (3) correlate the two, Assign ownership of 1,2 and finally assign an approver group to the roles.

## Dependencies and Prerequisites

.NET OIM connection
> .NET framework provided by OIM was utilized to secure connect to OIM as a read only account, each SQL call therefore needs to have a schema reset to see certain tables called

## Inputs


Input files
> Each run would need the fulfiller to go to the ticketing system and copy the ticket CR description into a text file. Put all said files in the ./input location

Container & Referenced Library
> the .NET module, its libraries, and the input folder are all located in the same folder. This can be zipped and shared amongst the team with all the required components self-contained to execute correctly

## Releases

> Version 1.1
  - functional and tested with QA data
  - outputs single LDIF in modify format with the same name "modified_" prepended to the name in the ./output/ folder location
  - can only handle a single ldif input per run
  - does not use the json config file --> assumes all user attributes in the input are to be modified if they contain the text "@target.com"
  - search/replace text is hardcoded:    "@target.com"

> Version 2.1
  - capability expanded to read in from multiple LDIF, loops through each LDIF file in input directory

> Version 2.2
  - regex used vs string.startswith executions to handle case insensitivity of LDIF ldifFiles
  - removed redundant processing
