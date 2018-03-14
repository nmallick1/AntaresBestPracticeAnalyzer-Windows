Checks to see if LocalCache is enabled or not.
If it is, then further checks to see the site's content to make sure it is < 1.5 GB. Large content size may cause the cache not to be populated as the copy may take longer than the timeout.
Also check to see that both LocalCache and DynamicCache are not enabled at the same time