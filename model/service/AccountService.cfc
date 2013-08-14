/*

    Slatwall - An Open Source eCommerce Platform
    Copyright (C) ten24, LLC
	
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
	
    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
	
    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
    
    Linking this program statically or dynamically with other modules is
    making a combined work based on this program.  Thus, the terms and
    conditions of the GNU General Public License cover the whole
    combination.
	
    As a special exception, the copyright holders of this program give you
    permission to combine this program with independent modules and your 
    custom code, regardless of the license terms of these independent
    modules, and to copy and distribute the resulting program under terms 
    of your choice, provided that you follow these specific guidelines: 

	- You also meet the terms and conditions of the license of each 
	  independent module 
	- You must not alter the default display of the Slatwall name or logo from  
	  any part of the application 
	- Your custom code must not alter or create any files inside Slatwall, 
	  except in the following directories:
		/integrationServices/

	You may copy and distribute the modified version of this program that meets 
	the above guidelines as a combined work under the terms of GPL for this program, 
	provided that you include the source code of that other code when and as the 
	GNU GPL requires distribution of source code.
    
    If you modify this program, you may extend this exception to your version 
    of the program, but you are not obligated to do so.

Notes:

*/
component extends="HibachiService" accessors="true" output="false" {
	
	property name="accountDAO" type="any";
	
	property name="emailService" type="any";
	property name="paymentService" type="any";
	property name="permissionService" type="any";
	property name="priceGroupService" type="any";
	property name="settingService" type="any";
	property name="siteService" type="any";
	property name="validationService" type="any";
	
	
	public string function getHashedAndSaltedPassword(required string password, required string salt) {
		return hash(arguments.password & arguments.salt, 'SHA-512');
	}
	
	public string function getPasswordResetID(required any account) {
		var passwordResetID = "";
		var accountAuthentication = getAccountDAO().getPasswordResetAccountAuthentication(accountID=arguments.account.getAccountID());
		
		if(isNull(accountAuthentication)) {
			var accountAuthentication = this.newAccountAuthentication();
			accountAuthentication.setExpirationDateTime(now() + 7);
			accountAuthentication.setAccount( arguments.account );
			
			accountAuthentication = this.saveAccountAuthentication( accountAuthentication );
		}
		
		return lcase("#arguments.account.getAccountID()##hash(accountAuthentication.getAccountAuthenticationID() & arguments.account.getAccountID())#");
	}
	
	// ===================== START: Logical Methods ===========================
	
	// =====================  END: Logical Methods ============================
	
	// ===================== START: DAO Passthrough ===========================
	
	public boolean function getPrimaryEmailAddressNotInUseFlag( required string emailAddress, string accountID ) {
		return getAccountDAO().getPrimaryEmailAddressNotInUseFlag(argumentcollection=arguments);
	}
	
	public any function getInternalAccountAuthenticationsByEmailAddress(required string emailAddress) {
		return getAccountDAO().getInternalAccountAuthenticationsByEmailAddress(argumentcollection=arguments);
	}
	
	public boolean function getAccountAuthenticationExists() {
		return getAccountDAO().getAccountAuthenticationExists();
	}
	
	public any function getAccountWithAuthenticationByEmailAddress( required string emailAddress ) {
		return getAccountDAO().getAccountWithAuthenticationByEmailAddress( argumentcollection=arguments );
	}
	
	// =====================  END: DAO Passthrough ============================
	
	// ===================== START: Process Methods ===========================
	
	// Account
	public any function processAccount_addAccountPayment(required any account, required any processObject) {
		
		// Get the populated newAccountPayment out of the processObject
		var newAccountPayment = processObject.getNewAccountPayment();
		
		// Make sure that this new accountPayment gets attached to the order
		if(isNull(newAccountPayment.getAccount())) {
			newAccountPayment.setAccount( arguments.account );
		}
		
		// If this is an existing account payment method, then we can pull the data from there
		if( len(arguments.processObject.getAccountPaymentMethodID()) ) {
			
			// Setup the newAccountPayment from the existing payment method
			var accountPaymentMethod = this.getAccountPaymentMethod( arguments.processObject.getAccountPaymentMethodID() );
			newAccountPayment.copyFromAccountPaymentMethod( accountPaymentMethod );
			
		// This is a new payment, so we need to setup the billing address and see if there is a need to save it against the account
		} else {
			
			// Setup the billing address as an accountAddress if it existed, otherwise the billing address will have most likely just been populated already
			if(!isNull(arguments.processObject.getAccountAddressID()) && len(arguments.processObject.getAccountAddressID())) {
				var accountAddress = this.getAccountAddress( arguments.processObject.getAccountAddressID() );
				
				if(!isNull(accountAddress)) {
					newAccountPayment.setBillingAddress( accountAddress.getAddress().copyAddress( true ) );
				}
			}
			
			// If saveAccountPaymentMethodFlag is set to true, then we need to save this object
			if(arguments.processObject.getSaveAccountPaymentMethodFlag()) {
				var newAccountPaymentMethod = this.newAccountPaymentMethod();
				newAccountPaymentMethod.copyFromAccountPayment( newAccountPayment );
				newAccountPaymentMethod.setAccount( arguments.account );
				
				newAccountPaymentMethod = this.saveAccountPaymentMethod();
			}

		}
		
		// Save the newAccountPayment
		newAccountPayment = this.saveAccountPayment( newAccountPayment );
		
		// If there are errors in the newAccountPayment after save, then add them to the account
		if(newAccountPayment.hasErrors()) {
			arguments.account.addError('accountPayment', rbKey('admin.entity.order.addAccountPayment_error'));
			
		// If no errors, then we can process a transaction
		} else {
			
			var transactionData = {
				amount = newAccountPayment.getAmount()
			};
			
			if(newAccountPayment.getAccountPaymentType().getSystemCode() eq "aptCharge") {
				if(newAccountPayment.getPaymentMethod().getPaymentMethodType() eq "creditCard") {
					transactionData.transactionType = 'authorizeAndCharge';
				} else {
					transactionData.transactionType = 'receive';	
				}
			} else {
				transactionData.transactionType = 'credit';
			}
			
			newAccountPayment = this.processAccountPayment(newAccountPayment, transactionData, 'createTransaction');
				
		}
		
		return arguments.account;
	}
	
	public any function processAccount_changePassword(required any account, required any processObject) {
		
		var authArray = arguments.account.getAccountAuthentications();
		for(var i=1; i<=arrayLen(authArray); i++) {
			
			// Find the non-integration authentication
			if(isNull(authArray[i].getIntegration()) && !isNull(authArray[i].getPassword())) {
				// Set the password
				authArray[i].setPassword( getHashedAndSaltedPassword(arguments.processObject.getPassword(), authArray[i].getAccountAuthenticationID()) );		
			}
		}
		
		return arguments.account;
	}
	
	public any function processAccount_create(required any account, required any processObject) {
		
		// Populate the account with the correct values that have been previously validated
		arguments.account.setFirstName( processObject.getFirstName() );
		arguments.account.setLastName( processObject.getLastName() );
		
		// If company was passed in then set that up
		if(!isNull(processObject.getCompany())) {
			arguments.account.setCompany( processObject.getCompany() );	
		}
		
		// If phone number was passed in the add a primary phone number
		if(!isNull(processObject.getPhoneNumber())) {
			var accountPhoneNumber = this.newAccountPhoneNumber();
			accountPhoneNumber.setAccount( arguments.account );
			accountPhoneNumber.setPhoneNumber( processObject.getPhoneNumber() );
		}
		
		// If email address was passed in then add a primary email address
		if(!isNull(processObject.getEmailAddress())) {
			var accountEmailAddress = this.newAccountEmailAddress();
			accountEmailAddress.setAccount( arguments.account );
			accountEmailAddress.setEmailAddress( processObject.getEmailAddress() );
		}
		
		// If the createAuthenticationFlag was set to true, the add the authentication
		if(processObject.getCreateAuthenticationFlag()) {
			var accountAuthentication = this.newAccountAuthentication();
			accountAuthentication.setAccount( arguments.account );
		
			// Put the accountAuthentication into the hibernate scope so that it has an id which will allow the hash / salting below to work
			getHibachiDAO().save(accountAuthentication);
		
			// Set the password
			accountAuthentication.setPassword( getHashedAndSaltedPassword(arguments.processObject.getPassword(), accountAuthentication.getAccountAuthenticationID()) );	
		}
		
		// Call save on the account now that it is all setup
		arguments.account = this.saveAccount(arguments.account);
		
		return arguments.account;
	}

	public any function processAccount_createPassword(required any account, required any processObject) {
		var accountAuthentication = this.newAccountAuthentication();
		accountAuthentication.setAccount( arguments.account );
	
		// Put the accountAuthentication into the hibernate scope so that it has an id which will allow the hash / salting below to work
		getHibachiDAO().save(accountAuthentication);
	
		// Set the password
		accountAuthentication.setPassword( getHashedAndSaltedPassword(arguments.processObject.getPassword(), accountAuthentication.getAccountAuthenticationID()) );
		
		return account;	
	}
	
	public any function processAccount_login(required any account, required any processObject) {
		
		// Take the email address and get all of the user accounts by primary e-mail address
		var accountAuthentications = getInternalAccountAuthenticationsByEmailAddress( emailAddress=arguments.processObject.getEmailAddress() );
		
		if(arrayLen(accountAuthentications)) {
			for(var i=1; i<=arrayLen(accountAuthentications); i++) {
				// If the password matches what it should be, then set the account in the session and 
				if(!isNull(accountAuthentications[i].getPassword()) && len(accountAuthentications[i].getPassword()) && accountAuthentications[i].getPassword() == getHashedAndSaltedPassword(password=arguments.processObject.getPassword(), salt=accountAuthentications[i].getAccountAuthenticationID())) {
					getHibachiSessionService().loginAccount( accountAuthentications[i].getAccount(), accountAuthentications[i] );
					return arguments.account;
				}
			}
			arguments.processObject.addError('password', rbKey('validate.account_authorizeAccount.password.incorrect'));
		} else {
			arguments.processObject.addError('emailAddress', rbKey('validate.account_authorizeAccount.emailAddress.notfound'));
		}
		
		return arguments.account;
	}
	
	public any function processAccount_logout( required any account ) {
		getHibachiSessionService().logoutAccount();
		
		return arguments.account;
	}
	
	public any function processAccount_forgotPassword( required any account, required any processObject ) {
		var forgotPasswordAccount = getAccountWithAuthenticationByEmailAddress( processObject.getEmailAddress() );
		
		if(!isNull(forgotPasswordAccount)) {
			
			// Get the site (this will return as a new site if no siteID)
			var site = getSiteService().getSite(arguments.processObject.getSiteID(), true);
			
			if(len(site.setting('siteForgotPasswordEmailTemplate'))) {
				
				var email = getEmailService().newEmail();
				var emailData = {
					accountID = forgotPasswordAccount.getAccountID(),
					emailTemplateID = site.setting('siteForgotPasswordEmailTemplate')
				};
				
				email = getEmailService().processEmail(email, emailData, 'createFromTemplate');
				
				email.setEmailTo( arguments.processObject.getEmailAddress() );
				
				email = getEmailService().processEmail(email, {}, 'addToQueue');
				
			} else {
				throw("No email template could be found.  Please update the site settings to define an 'Forgot Password Email Template'.");
			}
			
		} else {
			arguments.processObject.addError('emailAddress', rbKey('validate.account_forgotPassword.emailAddress.notfound'));
		}
		
		return arguments.account;
	}
	
	public any function processAccount_resetPassword( required any account, required any processObject ) {
		var changeProcessData = {
			password = arguments.processObject.getPassword(),
			passwordConfirm = arguments.processObject.getPasswordConfirm()
		};
		
		arguments.account = this.processAccount(arguments.account, changeProcessData, 'changePassword');
		
		// If there are no errors
		if(!arguments.account.hasErrors()) {
			// Get the temporary accountAuth
			var tempAA = getAccountDAO().getPasswordResetAccountAuthentication(accountID=arguments.account.getAccountID());
			
			// Delete the temporary auth
			tempAA.removeAccount();
			this.deleteAccountAuthentication( tempAA );
			
			// Then flush the ORM session so that an account can be logged in right away
			getHibachiDAO().flushORMSession();
		}
		
		return arguments.account;
	}
	
	public any function processAccount_setupInitialAdmin(required any account, required struct data={}, required any processObject) {
		
		// Populate the account with the correct values that have been previously validated
		arguments.account.setFirstName( processObject.getFirstName() );
		arguments.account.setLastName( processObject.getLastName() );
		if(!isNull(processObject.getCompany())) {
			arguments.account.setCompany( processObject.getCompany() );	
		}
		arguments.account.setSuperUserFlag( 1 );
		
		// Setup the email address
		var accountEmailAddress = this.newAccountEmailAddress();
		accountEmailAddress.setAccount(arguments.account);
		accountEmailAddress.setEmailAddress( processObject.getEmailAddress() );
		
		// Setup the authentication
		var accountAuthentication = this.newAccountAuthentication();
		accountAuthentication.setAccount( arguments.account );
		
		// Put the accountAuthentication into the hibernate scope so that it has an id
		getHibachiDAO().save(accountAuthentication);
		
		// Set the password
		accountAuthentication.setPassword( getHashedAndSaltedPassword(arguments.data.password, accountAuthentication.getAccountAuthenticationID()) );
		
		// Call save on the account now that it is all setup
		arguments.account = this.saveAccount(arguments.account);
		
		// Setup the Default to & from emails in the system to this users account
		var defaultSetupData = {
			emailAddress = processObject.getEmailAddress() 
		};
		getSettingService().setupDefaultValues( defaultSetupData );
		
		// Login the new account
		if(!arguments.account.hasErrors()) {
			getHibachiSessionService().loginAccount(account=arguments.account, accountAuthentication=accountAuthentication);	
		}
		
		return arguments.account;
	}
	
	// Account Loyalty Programs
	public any function processAccountLoyaltyProgram_itemsFulfilled(required any accountLoyaltyProgram, required struct data) {
	
		// Loop Over arguments.accountLoyaltyProgram.getLoyaltyProgramAccruements() as 'loyaltyProgramAccruement'
		for(var loyaltyProgramAccruement in arguments.accountLoyaltyProgram.getLoyaltyProgramAccruements()) {	
			
			// If loyaltyProgramAccruement eq 'fulfillItem' as the type, then based on the amount create a new transaction and apply that amount
			if (loyaltyProgramAccruement.getAccruementType() eq 'fulfillItem') {
				
				// Loop over the orderDeliveryItems in arguments.data.orderDelivery
				for(var orderDeliveryItem in arguments.data.orderDelivery.getOrderDeliveryItems()) {
					
					// START: Check Exclusions
		
					var hasExcludedProductType = false;
					// Check all of the exclusions for an excluded product type
					if(arrayLen(loyaltyProgramAccruement.getExcludedProductTypes())) {
						var excludedProductTypeIDList = "";
						for(var i=1; i<=arrayLen(loyaltyProgramAccruement.getExcludedProductTypes()); i++) {
							excludedProductTypeIDList = listAppend(excludedProductTypeIDList, loyaltyProgramAccruement.getExcludedProductTypes()[i].getProductTypeID());
						}
					
						for(var ptid=1; ptid<=listLen(arguments.orderItem.getSku().getProduct().getProductType().getProductTypeIDPath()); ptid++) {
							if(listFindNoCase(excludedProductTypeIDList, listGetAt(arguments.orderItem.getSku().getProduct().getProductType().getProductTypeIDPath(), ptid))) {
								hasExcludedProductType = true;
								break;
							}	
						}
					}
					
					// If anything is excluded then we return false
					if(	hasExcludedProductType
						||
						loyaltyProgramAccruement.hasExcludedProduct( orderDeliveryItem.getOrderItem().getSku().getProduct() )
						||
						loyaltyProgramAccruement.hasExcludedSku( orderDeliveryItem.getOrderItem().getSku() )
						||
						( arrayLen( loyaltyProgramAccruement.getExcludedBrands() ) && ( isNull( orderDeliveryItem.getOrderItem().getSku().getProduct().getBrand() ) || loyaltyProgramAccruement.hasExcludedBrand( orderDeliveryItem.getOrderItem().getSku().getProduct().getBrand() ) ) )
						) {
						return false;
					}
					
					// START: Check Inclusions
					var hasIncludedProductType = false;
					
					if(arrayLen(arguments.reward.getProductTypes())) {
						var includedPropertyTypeIDList = "";
						
						for(var i=1; i<=arrayLen(arguments.reward.getProductTypes()); i++) {
							includedPropertyTypeIDList = listAppend(includedPropertyTypeIDList, loyaltyProgramAccruement.getProductTypes()[i].getProductTypeID());
						}
						
						for(var ptid=1; ptid<=listLen(arguments.orderItem.getSku().getProduct().getProductType().getProductTypeIDPath()); ptid++) {
							if(listFindNoCase(includedPropertyTypeIDList, listGetAt(orderDeliveryItem.getOrderItem().getSku().getProduct().getProductType().getProductTypeIDPath(), ptid))) {
								hasIncludedProductType = true;
								break;
							}	
						}
					}
						
					// Verify that this orderDeliveryItem product is in the products, or skus for the accruement
					if ( hasIncludedProductType 
						|| loyaltyProgramAccruement.hasProduct(orderDeliveryItem.getOrderItem().getSku().getProduct()) 
						|| loyaltyProgramAccruement.hasSku(orderDeliveryItem.getOrderItem().getSku()) 
						|| (!isNull(orderDeliveryItem.getOrderItem().getSku().getProduct().getBrand()) && loyaltyProgramAccruement.hasBrand(orderDeliveryItem.getOrderItem().getSku().getProduct().getBrand())) 
						){
						 
						// TODO [paul]:Neet to add a check for excludes
						// TODO [paul]:THIS WILL NOT WORK -> loyaltyProgramAccruement.hasProductType(orderDeliveryItem.getOrderItem().getSku().getProduct().getProductType())
						// Look at PromotionService.cfc lines 926 - 940 for example
						
						// For each orderItem add a transaction record for the points accrued
						var accountLoayltyTransaction = this.newAccountLoyaltyTransaction();
						accountLoayltyTransaction.setAccount( accountLoyaltyProgram.getAccount() );
						accountLoayltyTransaction.setOrderItem( orderDeliveryItem.getOrderItem() );
						
						if ( loyaltyProgramAccruement.getPointType() eq 'fixed' ){
							accountLoayltyTransaction.setPointsIn( loyaltyProgramAccruement.getPoint() );
						}
						else if ( loyaltyProgramAccruement.getPointType() eq 'pricePerDollar' ) {
							accountLoayltyTransaction.setPointsIn( loyaltyProgramAccruement.getPoint() * (orderDeliveryItem.getQuantity() * orderDeliveryItem().getOrderItem().getPrice()) );
						}
					}
				}
			}
		}
	}
	
	public any function processAccountLoyaltyProgram_orderClosed(required any accountLoyaltyProgram, required struct data) {
		
		// Loop Over accountLoyaltyProgram.getLoyaltyProgram().getLoyaltyProgramAccruements() as 'loyaltyProgramAccruement'
		for(var loyaltyProgramAccruement in arguments.accountLoyaltyProgram.getLoyaltyProgramAccruements()) {	
			
			// If loyaltyProgramAccruement eq 'orderClosed' as the type
			if (loyaltyProgramAccruement.getAccruementType() eq 'orderClosed') {
				
				// TODO [paul]: Remove all of the below... there is no product checking for the accruement type of 'orderClosed'
				// TODO [paul]: keep in mind there is not going to be an orderDelivery in arguments.data, there will be an 'order'.
				
				if ( listFindNoCase("ostClosed",arguments.data.order.getOrderItemStatusType().getSystemCode()) ){
					var accountLoayltyTransaction = this.newAccountLoyaltyTransaction();
					accountLoayltyTransaction.setAccount( accountLoyaltyProgram.getAccount() );
					accountLoayltyTransaction.setOrder( arguments.data.order.getOrder() );
					
					//if ( loyaltyProgramAccruement.getPointType() eq 'fixed' ){
						accountLoayltyTransaction.setPointsIn( loyaltyProgramAccruement.getPoint() );
					//}
					//else if ( loyaltyProgramAccruement.getPointType() eq 'pricePerDollar' ) {
					//	accountLoayltyTransaction.setPointsIn( loyaltyProgramAccruement.getPoint() * (orderDeliveryItem.getQuantity() * orderDeliveryItem().getOrderItem().getPrice()) );
					//}	
				}	

			}
		}
	}
	
	public any function processAccountLoyaltyProgram_fulfillmentMethodUsed(required any accountLoyaltyProgram, required struct data) {
		
		// Loop Over accountLoyaltyProgram.getLoyaltyProgram().getLoyaltyProgramAccruements() as 'loyaltyProgramAccruement'
		for(var loyaltyProgramAccruement in arguments.accountLoyaltyProgram.getLoyaltyProgramAccruements()) {	
			
			// If loyaltyProgramAccruement eq 'fulfillmentMetodUsed' as the type
			if (loyaltyProgramAccruement.getAccruementType() eq 'fulfillmentMetodUsed') {
				
				// TODO [paul]: Same here, you don't need to check on the delivery items.  You just need to know if all the orderItems have a status of 'fulfilled'
				
				var allOrderItemsFulfilled = true;
				
				// Loop over the orderDeliveryItems in arguments.data.orderDelivery
				for(var orderDeliveryItem in arguments.data.orderDelivery.getOrderDeliveryItems()) {
						
					// Verify that this orderDeliveryItem product is in the productTypes, products, or skus for the accruement
					if ( listFindNoCase("oistFulfilled",orderDeliveryItem.getOrderItemStatusType().getSystemCode()) ){
						allOrderItemsFulfilled = false;
						break;
					}	
					
				}	
				
				if( allOrderItemsFulfilled ){
					
					var accountLoayltyTransaction = this.newAccountLoyaltyTransaction();
					accountLoayltyTransaction.setAccount( accountLoyaltyProgram.getAccount() );
					accountLoayltyTransaction.setOrderFulfillment( arguments.data.orderDelivery.getOrderDeliveryItems()[1].getOrderFulfillment() );
					
					//if ( loyaltyProgramAccruement.getPointType() eq 'fixed' ){
						accountLoayltyTransaction.setPointsIn( loyaltyProgramAccruement.getPoint() );
					//}
					//else if ( loyaltyProgramAccruement.getPointType() eq 'pricePerDollar' ) {
					//	accountLoayltyTransaction.setPointsIn( loyaltyProgramAccruement.getPoint() * (orderDeliveryItem.getQuantity() * orderDeliveryItem().getOrderItem().getPrice()) );
					//}
				}
			}
		}
		
	}
	
	public any function processAccountLoyaltyProgram_enrollment(required any accountLoyaltyProgram, required struct data) {
		
		// Loop Over accountLoyaltyProgram.getLoyaltyProgram().getLoyaltyProgramAccruements() as 'loyaltyProgramAccruement'
		for(var loyaltyProgramAccruement in arguments.accountLoyaltyProgram.getLoyaltyProgramAccruements()) {	
			
			// If loyaltyProgramAccruement eq 'enrollment' as the type
			if (loyaltyProgramAccruement.getAccruementType() eq 'enrollment') {
				
				// TODO [paul]: THERE IS NO ORDERDELIVERY!
				var accountLoayltyTransaction = this.newAccountLoyaltyTransaction();
				accountLoayltyTransaction.setAccount( accountLoyaltyProgram.getAccount() );
				accountLoayltyTransaction.setPointsIn( loyaltyProgramAccruement.getPoint() );
			}
		}
			
	}
	
	// Account Payment
	public any function processAccountPayment_createTransaction(required any accountPayment, required any processObject) {
		
		// Create a new payment transaction
		var paymentTransaction = getPaymentService().newPaymentTransaction();
		
		// Setup the accountPayment in the transaction to be used by the 'runTransaction'
		paymentTransaction.setAccountPayment( arguments.accountPayment );
		
		// Setup the transaction data
		transactionData = {
			transactionType = processObject.getTransactionType(),
			amount = processObject.getAmount()
		};
		
		// Run the transaction
		paymentTransaction = getPaymentService().processPaymentTransaction(paymentTransaction, transactionData, 'runTransaction');
		
		// If the paymentTransaction has errors, then add those errors to the orderPayment itself
		if(paymentTransaction.hasError('runTransaction')) {
			arguments.accountPayment.addError('createTransaction', paymentTransaction.getError('runTransaction'), true);
		}
		
		return arguments.accountPayment;	
	}
	
	// Account Payment Method
	public any function processAccountPaymentMethod_createTransaction(required any accountPaymentMethod, required any processObject) {
		
		// Create a new payment transaction
		var paymentTransaction = getPaymentService().newPaymentTransaction();
		
		// Setup the accountPayment in the transaction to be used by the 'runTransaction'
		paymentTransaction.setAccountPaymentMethod( arguments.accountPaymentMethod );
		
		// Setup the transaction data
		transactionData = {
			transactionType = processObject.getTransactionType(),
			amount = processObject.getAmount()
		};
		
		// Run the transaction
		paymentTransaction = getPaymentService().processPaymentTransaction(paymentTransaction, transactionData, 'runTransaction');
		
		// If the paymentTransaction has errors, then add those errors to the orderPayment itself
		if(paymentTransaction.hasError('runTransaction')) {
			arguments.accountPaymentMethod.addError('createTransaction', paymentTransaction.getError('runTransaction'), true);
		}
		
		return arguments.accountPaymentMethod;	
	}
	
	// =====================  END: Process Methods ============================
	
	// ====================== START: Save Overrides ===========================
	
	public any function saveAccountPaymentMethod(required any accountPaymentMethod, struct data={}, string context="save") {
		// See if the accountPaymentMethod was new
		var wasNew = arguments.accountPaymentMethod.getNewFlag();
		
		// Call the generic save method to populate and validate
		arguments.accountPaymentMethod = save(arguments.accountPaymentMethod, arguments.data, arguments.context);
		
		// If the order payment does not have errors, then we can check the payment method for a saveTransaction
		if(wasNew && !arguments.accountPaymentMethod.hasErrors() && !isNull(arguments.accountPaymentMethod.getPaymentMethod().getSaveAccountPaymentMethodTransactionType()) && len(arguments.accountPaymentMethod.getPaymentMethod().getSaveAccountPaymentMethodTransactionType()) && arguments.accountPaymentMethod.getPaymentMethod().getSaveAccountPaymentMethodTransactionType() neq "none") {
			
			// Setup transaction data
			var transactionData = {
				amount = 0,
				transactionType = arguments.accountPaymentMethod.getPaymentMethod().getSaveAccountPaymentMethodTransactionType()
			};
			
			// Clear out any previous 'createTransaction' process objects
			arguments.accountPaymentMethod.clearProcessObject( 'createTransaction' );
			
			arguments.accountPaymentMethod = this.processAccountPaymentMethod(arguments.accountPaymentMethod, transactionData, 'createTransaction');
		}
		
		return arguments.accountPaymentMethod;
		
	}
		
	public any function savePermissionGroup(required any permissionGroup, struct data={}, string context="save") {
	
		arguments.permissionGroup.setPermissionGroupName( arguments.data.permissionGroupName );
		
		// As long as permissions were passed in we can set those up
		if(structKeyExists(arguments.data, "permissions")) {
			// Loop over all of the permissions that were passed in.
			for(var i=1; i<=arrayLen(arguments.data.permissions); i++) {
				
				var pData = arguments.data.permissions[i];	
				var pEntity = this.getPermission(arguments.data.permissions[i].permissionID, true);
				pEntity.populate( pData );
				
				// Delete this permssion
				if(!pEntity.isNew() && (isNull(pEntity.getAllowCreateFlag()) || !pEntity.getAllowCreateFlag()) && (isNull(pEntity.getAllowReadFlag()) || !pEntity.getAllowReadFlag()) && (isNull(pEntity.getAllowUpdateFlag()) || !pEntity.getAllowUpdateFlag()) && (isNull(pEntity.getAllowDeleteFlag()) || !pEntity.getAllowDeleteFlag()) && (isNull(pEntity.getAllowProcessFlag()) || !pEntity.getAllowProcessFlag()) && (isNull(pEntity.getAllowActionFlag()) || !pEntity.getAllowActionFlag()) ) {
					arguments.permissionGroup.removePermission( pEntity );
					this.deletePermission( pEntity );
				// Otherwise Save This Entity
				} else if ((!isNull(pEntity.getAllowCreateFlag()) && pEntity.getAllowCreateFlag()) || (!isNull(pEntity.getAllowReadFlag()) && pEntity.getAllowReadFlag()) || (!isNull(pEntity.getAllowUpdateFlag()) && pEntity.getAllowUpdateFlag()) || (!isNull(pEntity.getAllowDeleteFlag()) && pEntity.getAllowDeleteFlag()) || (!isNull(pEntity.getAllowProcessFlag()) && pEntity.getAllowProcessFlag()) || (!isNull(pEntity.getAllowActionFlag()) && pEntity.getAllowActionFlag())) {
					getAccountDAO().save( pEntity );
					arguments.permissionGroup.addPermission( pEntity );
				}
			}
		}
		
		// Validate the permission group
		arguments.permissionGroup.validate(context='save');
		
		// Setup hibernate session correctly if it has errors or not
		if(!arguments.permissionGroup.hasErrors()) {
			getAccountDAO().save( arguments.permissionGroup );
		}
		
		return arguments.permissionGroup;
	}
	
	// ======================  END: Save Overrides ============================
	
	// ==================== START: Smart List Overrides =======================
	

	public any function getAccountSmartList(struct data={}, currentURL="") {
		arguments.entityName = "SlatwallAccount";
		
		var smartList = getHibachiDAO().getSmartList(argumentCollection=arguments);
		
		smartList.joinRelatedProperty("SlatwallAccount", "primaryEmailAddress", "left");
		smartList.joinRelatedProperty("SlatwallAccount", "primaryPhoneNumber", "left");
		smartList.joinRelatedProperty("SlatwallAccount", "primaryAddress", "left");
		
		smartList.addKeywordProperty(propertyIdentifier="firstName", weight=1);
		smartList.addKeywordProperty(propertyIdentifier="lastName", weight=1);
		smartList.addKeywordProperty(propertyIdentifier="company", weight=1);
		smartList.addKeywordProperty(propertyIdentifier="primaryEmailAddress.emailAddress", weight=1);
		smartList.addKeywordProperty(propertyIdentifier="primaryPhoneNumber.phoneNumber", weight=1);
		smartList.addKeywordProperty(propertyIdentifier="primaryAddress.streetAddress", weight=1);
		
		return smartList;
	}
	
	public any function getAccountEmailAddressSmartList(struct data={}, currentURL="") {
		arguments.entityName = "SlatwallAccountEmailAddress";
		
		var smartList = getHibachiDAO().getSmartList(argumentCollection=arguments);
		
		smartList.joinRelatedProperty("SlatwallAccountEmailAddress", "accountEmailType", "left");
		
		return smartList;
	}
	
	public any function getAccountPhoneNumberSmartList(struct data={}, currentURL="") {
		arguments.entityName = "SlatwallAccountPhoneNumber";
		
		var smartList = getHibachiDAO().getSmartList(argumentCollection=arguments);
		
		smartList.joinRelatedProperty("SlatwallAccountPhoneNumber", "accountPhoneType", "left");
		
		return smartList;
	}
	
	
	// ====================  END: Smart List Overrides ========================
	
	// ====================== START: Get Overrides ============================
	
	// ======================  END: Get Overrides =============================
	
	// ===================== START: Delete Overrides ==========================
	
	public boolean function deleteAccount(required any account) {
	
		// Check delete validation
		if(arguments.account.isDeletable()) {
			
			// Remove the primary fields so that we can delete this entity
			arguments.account.setPrimaryEmailAddress(javaCast("null", ""));
			arguments.account.setPrimaryPhoneNumber(javaCast("null", ""));
			arguments.account.setPrimaryAddress(javaCast("null", ""));
			
			getAccountDAO().removeAccountFromAllSessions( arguments.account.getAccountID() );
			getAccountDAO().removeAccountFromAuditProperties( arguments.account.getAccountID() );
			
			return delete( arguments.account );
		}
		
		return delete( arguments.account );
	}
	
	public boolean function deleteAccountEmailAddress(required any accountEmailAddress) {
		
		// Check delete validation
		if(arguments.accountEmailAddress.isDeletable()) {
			
			// If the primary email address is this e-mail address then set the primary to null
			if(arguments.accountEmailAddress.getAccount().getPrimaryEmailAddress().getAccountEmailAddressID() eq arguments.accountEmailAddress.getAccountEmailAddressID()) {
				arguments.accountEmailAddress.getAccount().setPrimaryEmailAddress(javaCast("null",""));
			}
			
			return delete(arguments.accountEmailAddress);
		}
		
		return false;
	}
	
	public boolean function deleteAccountPhoneNumber(required any accountPhoneNumber) {
		
		// Check delete validation
		if(arguments.accountPhoneNumber.isDeletable()) {
			
			// If the primary email address is this e-mail address then set the primary to null
			if(arguments.accountPhoneNumber.getAccount().getPrimaryPhoneNumber().getAccountPhoneNumberID() eq arguments.accountPhoneNumber.getAccountPhoneNumberID()) {
				arguments.accountPhoneNumber.getAccount().setPrimaryPhoneNumber(javaCast("null",""));
			}
			
			return delete(arguments.accountPhoneNumber);
		}
		
		return false;
	}
	
	public boolean function deleteAccountAddress(required any accountAddress) {
		
		// Check delete validation
		if(arguments.accountAddress.isDeletable()) {

			// If the primary email address is this e-mail address then set the primary to null
			if(arguments.accountAddress.getAccount().getPrimaryAddress().getAccountAddressID() eq arguments.accountAddress.getAccountAddressID()) {
				arguments.accountAddress.getAccount().setPrimaryAddress(javaCast("null",""));
			}
			
			// Remove from all orderFulfillments
			getAccountDAO().removeAccountAddressFromOrderFulfillments( accountAddressID = arguments.accountAddress.getAccountAddressID() );
			
			return delete(arguments.accountAddress);
		}
		
		return false;
	}
	
	// =====================  END: Delete Overrides ===========================
	
}

