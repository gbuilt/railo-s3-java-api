<!---

	s3api.cfc

	Allows File Upload to S3 with public or private access (acl) and correct metadata.
	Allows links to public and private files with exiry timeouts.

	Copyright (c) 2012, Garrett Bach

	Licensed under the Apache License, Version 2.0 (the "License").
	You may not use this file except in compliance with the License.
	You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

	Unless required by applicable law or agreed to in writing, software
	distributed under the License is distributed on an "AS IS" BASIS,
	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	See the License for the specific language governing permissions and
	limitations under the License.

	Example usage:

	Application Scope Caching: <cfset application.s3api = createObject("component","s3api").init() />
	<cfset command = application.s3api.upload(filepath="#expandPath('/')#tmp/testfile.txt",s3path="/permanent/location/testfile.txt") />
	<cfset command = application.s3api.getlink(s3path="") />

--->

<cfcomponent output="false">
	
	
	
	<!--- Create the java S3 connector object --->
	<cfset this.s3.bucket = "[Bucket-Name]" />
	<cfset this.s3.client = createObject("java","com.amazonaws.services.s3.AmazonS3Client").init(
								createObject("java","com.amazonaws.auth.BasicAWSCredentials").init(
									"[AWS-KEY]",
									"[AWS-SECRET]"
								)
							) />
	<!--- 
		I recommend *not* keeping the AWS-SECRET in plain text in this file.
		If there are any errors, parts of your source code may appear on screen, potentially exposing your AWS-SECRET.
		You can set the KEY and SECRET in the Application.cfc 'this.s3.key' and 'this.s3.secret' or other scopes.
		Or you could even do something like this below. There's many ways to protect it. Do something.
			Decrypt("LonGEnCrYPtEdSeCrETLonGEnCrYPtEdSeCrETLonGEnCrYPtEdSeCrETLonGEn",application.decryptkey, "AES", "Base64")
	 --->
	
	
	<!--- default init function for cached objects --->
	<cffunction name="init" access="public" output="false">
		<cfreturn this>
	</cffunction>
	
	
	
	<!--- Uploads a fil to S3 with proper "content-type" metadata and selected ACL (private/). --->	
	<cffunction name="upload" access="public" output="false">
		<cfargument name="filepath" type="any" required="No" default="" /><!--- including already expandpath full path --->
		<cfargument name="s3path" type="any" required="No" default="" /><!--- including target file name --->
		<cfargument name="access" type="any" required="No" default="Private" /><!--- Private/Public --->
		<cfif (LEN(TRIM(arguments.filepath)) EQ 0) OR (!fileExists(arguments.filepath))>
			<cfreturn "" />
		</cfif>
		
		<!--- Container and initialization for local variables --->
		<cfset var VARS = structNew() />
		<cfset VARS.filepath = arguments.filepath />
		<cfset VARS.s3path = arguments.s3path />
		<!--- Missing target file name? Take it from the source. --->
		<cfif (ListLen(VARS.s3path,".") IS 1) AND (ListLast(VARS.filepath,"/") NEQ ListLast(VARS.s3path,"/"))>
			<cfset VARS.s3path = VARS.s3path & "/" & ListLast(VARS.filepath,"/") />
		</cfif>
		<cfset VARS.s3path = ArrayToList(ListToArray(VARS.s3path,"/"),"/") /><!--- removes double //'s and leading /'s --->
		<cfset VARS.filename = ListLast(VARS.s3path,"/") />
		
		<CFTRY>
			<!--- Read the file for sending to S3 --->
			<cfset VARS.javafileobj = createObject("java", "java.io.File").init(VARS.filepath) />
			
			<!--- Create the PutObject with the intended location (path) and  on S3 --->
			<cfset VARS.s3put = createObject("java","com.amazonaws.services.s3.model.PutObjectRequest").init("#this.s3.bucket#", "#VARS.s3path#", VARS.javafileobj) />
			
			<!--- Set the metedata fields for Content Type and Content Disposition --->
			<cfset VARS.s3meta = createObject("java","com.amazonaws.services.s3.model.ObjectMetadata") />
			<cfset VARS.s3meta.setContentType("#getPageContext().getServletContext().getMimeType(VARS.filepath)#") /><!--- Is this the best way? --->
			<cfset VARS.s3meta.setContentDisposition("inline; filename=#VARS.filename#") /><!--- suggest filename for download else name becomes full path with '_'s --->
			<cfset VARS.s3put.setMetadata(VARS.s3meta) />
			
			<!--- Set the ACL (Access Control List) --->
			<cfset VARS.s3acl = createObject("java","com.amazonaws.services.s3.model.CannedAccessControlList") /><!--- Usage: .Private or .PublicRead --->
			<cfset VARS.s3put.setCannedAcl(arguments.access=="Private"?VARS.s3acl.Private:VARS.s3acl.PublicRead) />
			
			<!--- The actual upload to s3 -- very simple --->
			<cfset VARS.s3result = this.s3.client.putObject(VARS.s3put) />
			
			<!--- All done - return the S3 file path (key) --->
			<cfreturn VARS.s3path />
			
			<CFCATCH type="any">
				<cfreturn "" />
			</CFCATCH>
		</CFTRY>
	</cffunction>



	<cffunction name="getlink" access="public" output="false">
		<cfargument name="s3path" type="any" required="No" default="" /><!--- S3 file key --->
		<cfargument name="expires" type="any" required="No" default="10" /><!--- Minutes until the link expires --->
		<cfif (LEN(TRIM(arguments.s3path)) EQ 0)>
			<cfreturn "" />
		</cfif>
		<CFTRY>
			<cfset var VARS = structNew() />
			<cfset VARS.s3path = ArrayToList(ListToArray(arguments.s3path,"/"),"/") /><!--- removes double //'s and leading /'s --->
			<cfset VARS.ispublic = false />
			<cfset VARS.acl = this.s3.client.getObjectAcl(this.s3.bucket, VARS.s3path) />
			<cfset VARS.accessList = VARS.acl.getGrants().toArray() />
			<cfif (ArrayLen(VARS.accessList) GT 1)>
				<cfloop from="1" to="#ArrayLen(VARS.accessList)#" index="VARS.ai">
					<cfset VARS.accessee = VARS.accessList[VARS.ai] />
					<!--- http://acs.amazonaws.com/groups/global/AllUsers AND READ --->
					<cfif (LCASE(ListLast(VARS.accessee.getGrantee().getIdentifier(),"/")) IS "allusers") AND (LCASE(VARS.accessee.getPermission().name()) IS "read")>
						<cfset VARS.ispublic = true />
					</cfif>
				</cfloop>
			</cfif>
			<!--- If ACL is Private - Get authenticated link and test the download and prompted file name --->
			<cfif (VARS.ispublic)>
				<cfreturn this.s3.client.generatePresignedUrl("#this.s3.bucket#", "#VARS.s3path#", dateAdd("m", arguments.expires, request.now)).toString() />
			<cfelse>
				<cfreturn "https://#this.s3.bucket#.s3.amazonaws.com/#VARS.s3path#" />
			</cfif>
			<CFCATCH type="any">
				<cfreturn "" /><!--- File doesn't exist in S3 --->
			</CFCATCH>
		</CFTRY>
	</cffunction>
	
	
	
</cfcomponent>
