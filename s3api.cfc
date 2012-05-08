<!---

	s3api.cfc

	Allows File Upload to S3 with public or private access (acl) and correct metadata (auto-detected content-type and file-name).
	Allows S3 Oject Copy (duplicate) to another location within the same bucket.
	Allowed S3 Object delete.
	Allows links to public objects without exiration, and private objects with exiration on authenticated link.
	Allows S3 Directory listing - can be used to verify existence of a single object.


	Requirements:

	AWS JAVA API Jar file located in the Railo (or coldfusion) [home]/lib path or known mapping. If it's a local subdirectory
	or mapping be sude to  change the 'com.amazonaws' method prefix to your custom path in 'init', 'upload', and copy' methods. 
	'(Remember, use periods in place of slashes for your local subdirectory path.)


	Example usage:

	Application Scople Caching: <cfset application.s3api = createObject("component","s3api").init() />
	<cfset command = application.s3api.upload(source="#expandPath('/')#tmp/testfile.txt",destination="/permanent/location/testfile.txt") />
	<cfset command = application.s3api.getlink(file="") />


	Copyright (c) 2012, GBUILT

	Licensed under the Apache License, Version 2.0 (the "License").
	You may not use this file except in compliance with the License.
	You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

	Unless required by applicable law or agreed to in writing, software distributed under the License is distributed
	on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	See the License for the specific language governing permissions and limitations under the License.

--->

<cfcomponent output="false">
	
	<!--- 
		I recommend not keeping the AWS-SECRET in plain text in this file.
		If there are any errors, parts of your source code may appear on screen, potentially exposing your AWS-SECRET.
		You can set the KEY and SECRET in the Application.cfc 'this.s3.key' and 'this.s3.secret' or other scopes.
		Or you could even do something like this below. There's many ways to protect it. Do something.
			Decrypt("LonGEnCrYPtEdSeCrETLonGEnCrYPtEdSeCrETLonGEnCrYPtEdSeCrETLonGEn","sOmEValIdLEnGtHSTrINg", "AES", "Base64")
		You can us this command below to encrypt it once and then pass the ecnrypted string in to be derpted here.
		As long as the two strings (encrypted secret and decrypt key) are not in plain text in the same file your risks are minimal.
			Encrypt("tHEActUaLs3LOnGSEcrETtHEActUaLs3LOnGSEcrETtHEActUaLs3LOnGSEcrET","sOmEValIdLEnGtHSTrINg", "AES", "Base64")
	 --->
	
	<!--- default init function for cached objects --->
	<cffunction name="init" access="public" returns="object" output="false">
		<cfargument name="bucket" type="string" required="YES" /><!--- The S3 Bucket name, used in all methods. --->
		<cfargument name="key" type="string" required="YES" /><!--- S3 Key (short, okay to be plain text). --->
		<cfargument name="secretenc" type="string" required="YES" /><!--- S3 Secret (Very important to keep private!). --->
		<!--- Create the java S3 connector object --->
		<cfset this.bucket = arguments.bucket />
		<cfset this.client = createObject("java","com.amazonaws.services.s3.AmazonS3Client").init(
									createObject("java","com.amazonaws.auth.BasicAWSCredentials").init(
										arguments.key,
										Decrypt(arguments.secretenc, 'yOUrdEcrYPtiONKEy', 'AES', 'Base64')
									)
								) />
		<cfreturn this />
	</cffunction>
	
	
	
	<!--- Uploads a file to S3 with proper "content-type" metadata and selected ACL (Private/PublicRead). --->
	<cffunction name="upload" access="public" returns="string" output="false">
		<cfargument name="source" type="string" required="No" default="" /><!--- include already expandpath for full path --->
		<cfargument name="destination" type="string" required="No" default="" /><!--- target directory including target file name --->
		<cfargument name="access" type="string" required="No" default="Private" /><!--- Private / PublicRead --->
		<CFTRY>
			<!--- validate required arguments --->
			<cfif (LEN(TRIM(arguments.source)) EQ 0) OR (!fileExists(arguments.source))>
				<cfreturn "" />
			</cfif>
		
			<!--- Container and initialization for local variables --->
			<cfset var VARS = structNew() />
			<cfset VARS.source = arguments.source />
			<cfset VARS.destination = arguments.destination />
			<!--- Missing target file name? Take it from the source. --->
			<cfif (ListLen(VARS.destination,".") IS 1) AND (ListLast(VARS.source,"/") NEQ ListLast(VARS.destination,"/"))>
				<cfset VARS.destination = VARS.destination & "/" & ListLast(VARS.source,"/") />
			</cfif>
			<cfset VARS.destination = ArrayToList(ListToArray(VARS.destination,"/"),"/") /><!--- removes double //'s and leading /'s --->
			<cfset VARS.filename = ListLast(VARS.destination,"/") />
		
			<!--- Read the file for sending to S3 --->
			<cfset VARS.javafileobj = createObject("java", "java.io.File").init(VARS.source) />
			
			<!--- Create the PutObject with the intended location (path) and  on S3 --->
			<cfset VARS.s3put = createObject("java","com.amazonaws.services.s3.model.PutObjectRequest").init("#this.bucket#", "#VARS.destination#", VARS.javafileobj) />
			
			<!--- Set the metedata fields for Content Type and Content Disposition --->
			<cfset VARS.s3meta = createObject("java","com.amazonaws.services.s3.model.ObjectMetadata") />
			<cfset VARS.s3meta.setContentType("#getPageContext().getServletContext().getMimeType(LCASE(VARS.filename))#") /><!--- Is this the best way? --->
			<cfset VARS.s3meta.setContentDisposition("inline; filename=#VARS.filename#") /><!--- suggest filename for download else name becomes full path with '_'s --->
			<cfset VARS.s3put.setMetadata(VARS.s3meta) />
			
			<!--- Set the ACL (Access Control List) --->
			<cfset VARS.s3acl = createObject("java","com.amazonaws.services.s3.model.CannedAccessControlList") /><!--- Usage: .Private or .PublicRead --->
			<cfset VARS.s3put.setCannedAcl(arguments.access=="Private"?VARS.s3acl.Private:VARS.s3acl.PublicRead) />
			
			<!--- The actual upload to s3 -- very simple --->
			<cfset VARS.s3result = this.client.putObject(VARS.s3put) />
			
			<!--- All done - return the S3 file path (key) --->
			<cfreturn VARS.destination />
			
		<CFCATCH type="any">
			<cfreturn "" />
		</CFCATCH>
		</CFTRY>
	</cffunction>
	
	
	
	<!--- duplicates an S3 object within the bucket. --->
	<cffunction name="copy" access="public" returns="string" output="false">
		<!--- Usage: <cfset variables.s3action = application.s3api.copy(variables.s3path, variables.s3dest) /> --->
		<!--- Returns: URL of new object, or blank if failure --->
		<cfargument name="source" type="string" required="No" default="" /><!--- exact source S3 key (full path) --->
		<cfargument name="destination" type="string" required="No" default="" /><!--- exact target S3 key (full path) --->
		<CFTRY>
			<!--- validate required arguments --->
			<cfif (LEN(TRIM(arguments.source)) EQ 0) OR (LEN(TRIM(arguments.destination)) EQ 0)>
				<cfreturn "" />
			</cfif>
			<cfset arguments.source = ArrayToList(ListToArray(arguments.source,"/"),"/") /><!--- removes double //'s and leading /'s --->
			<cfset arguments.destination = ArrayToList(ListToArray(arguments.destination,"/"),"/") /><!--- removes double //'s and leading /'s --->
			<cfset var VARS = structNew() />
			<cfset VARS.s3meta = this.client.getObjectMetadata(this.bucket, arguments.source) />
			<cfset VARS.s3meta.setContentDisposition("inline; filename=#ListLast(arguments.destination,'/')#") /><!--- suggest filename for download --->
			<cfset VARS.s3copy = createObject("java","com.amazonaws.services.s3.model.CopyObjectRequest").init(
												this.bucket, arguments.source, 
												this.bucket, arguments.destination
											) />
			<cfset VARS.s3copy.withNewObjectMetadata(VARS.s3meta) />
			<cfset this.client.copyObject(VARS.s3copy) />
			<cfreturn arguments.destination />
		<CFCATCH type="any">
			<cfreturn "" />
		</CFCATCH>
		</CFTRY>
	</cffunction>
	
	
	
	<!--- Deleted an S3 object. --->
	<cffunction name="delete" access="public" returns="boolean" output="false">
		<!--- Usage: <cfset variables.s3action = application.s3api.delete(variables.s3dest) /> --->
		<!--- Returns: true/false --->
		<cfargument name="s3path" type="string" required="No" default="" /><!--- include already expandpath for full path --->
		<CFTRY>
			<!--- validate required arguments --->
			<cfif (LEN(TRIM(arguments.s3path)) EQ 0)>
				<cfreturn false />
			</cfif>
			<cfset this.client.deleteObject(this.bucket, ArrayToList(ListToArray(arguments.s3path,"/"),"/")) />
			<cfreturn true />
			<!--- 
				The 'Delete' java api call returns 'VOID' no matter if it didn't exist or if it was successful.
				This 'delete' cfc method either errors (returning 'false') or the target doesn't exists,
				if it didn't exist before = ok, if it was just delete = ok, desired result anyway,
				so we return true either way after actually triggering the S3 delete command.
			 --->
		<CFCATCH type="any">
			<cfreturn false />
		</CFCATCH>
		</CFTRY>
	</cffunction>



	<!--- Returns an array of files within the given s3 directory path. if no path is provided it returns the whole bucket. --->
	<!--- Use this to do a basic 'FileExists()' type of action on a single S3 object. --->
	<cffunction name="dirlist" access="public" returns="array" output="false">
		<!--- Usage: <cfset variables.s3list = application.s3api.dirlist(variables.s3path) /> --->
		<!--- Returns: the public or authenticated+expiry URL, or blank if it failed --->
		<cfargument name="s3path" type="string" required="No" default="" /><!--- Full Path --->
		<CFTRY>
			<!--- validate required arguments --->
			<cfif (LEN(TRIM(arguments.s3path)) EQ 0)>
				<cfreturn arrayNew() /><!--- Empty array = File doesn't exist in S3 --->
			</cfif>
			<cfset arguments.s3path = ArrayToList(ListToArray(arguments.s3path,"/"),"/") /><!--- removes double //'s and leading /'s --->
			<cfset var VARS = structNew() />
			<!--- get the list --->
			<cfset VARS.s3summary = this.client.listObjects(this.bucket,arguments.s3path).getObjectSummaries() />
			<!--- loop through the comples java object to generate a new simple array of results --->
			<cfset VARS.s3match = arrayNew() /><!--- default to empty array = File doesn't exist in S3 --->
			<cfloop from="1" to="#arrayLen(VARS.s3summary)#" index="VARS.i">
				<cfset arrayAppend(VARS.s3match,VARS.s3summary[VARS.i].getKey()) />
			</cfloop>
			<cfreturn VARS.s3match />
		<CFCATCH type="any">
			<cfreturn arrayNew() /><!--- Empty array = File doesn't exist in S3 --->
		</CFCATCH>
		</CFTRY>
	</cffunction>
	


	<!--- Generates a download link for an S3 file. --->
	<cffunction name="getlink" access="public" returns="string" output="No">
		<!--- Usage: <cfset variables.s3link = application.s3api.getlink(variables.s3key) />
			Returns: the public or authenticated+expiry URL, or blank if it failed
			NOTE: 	On "expires", pass in a zero and this will flag the code below that the file should be publc = no auth/exp reqired.
					Example: application.s3api.getlink(variables.s3key,0)
		 --->
		<cfargument name="s3path" type="string" required="No" default="" /><!--- S3 file key, full path --->
		<cfargument name="expires" type="numeric" required="No" default="10" /><!--- Minutes until the link expires --->
		<CFTRY>
			<!--- validate required arguments --->
			<cfif (LEN(TRIM(arguments.s3path)) EQ 0)>
				<cfreturn "" />
			</cfif>
			<cfset var VARS = structNew() />
			<cfset VARS.s3path = ArrayToList(ListToArray(arguments.s3path,"/"),"/") /><!--- removes double //'s and leading /'s --->
			<!--- Do we need an authenticated link with expiration?  If it's a publicly accessible file we can skip the aws request. --->
			<cfset VARS.ispublic = arguments.expires EQ 0 ? true : false />
			<cfif (!VARS.ispublic)><!--- if 'public' access is unknown, then hit S3 to check if it's public before generating S3 auth link with expiry --->
				<cfset VARS.acl = this.client.getObjectAcl(this.bucket, VARS.s3path) />
				<cfset VARS.accessList = VARS.acl.getGrants().toArray() />
				<cfif (ArrayLen(VARS.accessList) GT 1)>
					<cfloop from="1" to="#ArrayLen(VARS.accessList)#" index="VARS.ai"><!--- Is there an easier way to do this? --->
						<cfset VARS.accessee = VARS.accessList[VARS.ai] />
						<!--- http://acs.amazonaws.com/groups/global/AllUsers AND READ --->
						<cfif (LCASE(ListLast(VARS.accessee.getGrantee().getIdentifier(),"/")) IS "allusers") AND (LCASE(VARS.accessee.getPermission().name()) IS "read")>
							<cfset VARS.ispublic = true />
						</cfif>
					</cfloop>
				</cfif>
			</cfif>
			<!--- If ACL is Private - Get authenticated link and test the download and prompted file name --->
			<cfif (VARS.ispublic)>
				<cfreturn "https://#this.bucket#.s3.amazonaws.com/#VARS.s3path#" />
			<cfelse>
				<!--- we need an authenticated URL with expiration --->
				<cfreturn this.client.generatePresignedUrl("#this.bucket#", "#VARS.s3path#", dateAdd("m", arguments.expires, request.now)).toString() />
			</cfif>
		<CFCATCH type="any">
			<cfreturn "" /><!--- File doesn't exist in S3 --->
		</CFCATCH>
		</CFTRY>
	</cffunction>
	
	
	
	<!--- Returns an array of files within the given s3 directory path. if no path is provided it returns the whole bucket. --->
	<!--- Use this to do a basic 'FileExists()' type of action on a single S3 object. --->
	<cffunction name="proxy" access="remote">
		<!--- Usage: <img src="/s3api.cfc?method=proxy&s3path=variables.s3key,0)#" /> --->
		<!--- Returns: nothing - performs relocation to actual s3 file --->
		<cfargument name="s3path" type="string" required="No" default="" /><!--- S3 file key, full path --->
		<cfargument name="expires" type="string" required="No" default="10" /><!--- Minutes until the link expires --->
		<cfheader statuscode="302" statustext="Moved Temporarily" />
		<cfheader name="Location" value="#application.s3api.getlink(arguments.s3path,arguments.expires)#" />
		<!--- LET S3 HANDLE THE HEADERS AND FILE NAMING - IT WORKS! --->
	</cffunction>
	
	
	
</cfcomponent>