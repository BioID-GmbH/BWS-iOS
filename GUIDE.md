# Developer Guide

There are many ways to integrate this code into your iOS app. Here is one way. 

## Files required
Add the following files from the **captureView** folder to your Xcode project:

- `CaptureConfiguration.h`
- `CaptureConfiguration.m`
- `CaptureViewController.h`
- `CaptureConfiguration.m`

- `3DHead.dae`
Please take a look at section **Add the 3D head**.

- `Localizable.strings`
Supported languages are currently **EN** (en.lproj) and **DE** (de.lproj).


**Attention:**

Check in your app in the file Info.plist that the item UIRequiresFullScreen is set to YES.
If this item is not present, please add this item to your Info.plist. Otherwise the CaptureViewController will not
correctly work in iOS 9 combined with new iPad devices that support Split Screen/View of multiple apps.


## Add the 3D head
Go to Xcode menu *File > New > File*

Now you are in the `Choose a template for new file:` dialog. 
Select *iOS > Resource* on the left panel.

Then open the right panel and select `Asset Catalog` and click `Next`. 
The `Save As` dialog appears. Save the asset as `art.scnassets`

Then click on the `Create` button. The dialog `You have used the extension “.scnassets” at …` will open.
Click `Use .scnassets` button.

Now add the 3DHead.dae – only copy this file into your folder `art.scnassets`.


## Create a UIViewController in the Main.storyboard
Next open Show the Identity inspector panel. For the custom class enter CaptureViewController in the class field.
Select *View* in the Capture View Controller Scene.
Right click on *View* - Select `Referencing Outlet` and drag the mouse pointer to the CaptureViewController in the Interface Builder. Now the dialog opens with `previewView` and `view` selection. Select the `previewView`.
After that you see that the View in the Capture View Controller Scene changed from `View` to `Preview View`.


## Add segue to CaptureViewController
After you have set a segue to CaptureViewController, specify `showCaptureView`
in the Storyboard Segue in the identifier field and set `Kind` to `Present Modally`.


## How to call the CaptureViewController for enrollment or verification
Finally, take a look at BioIDSample Source Code to see how to call the CaptureViewController for enrollment or verification. This code is implemented in the `ViewController.m` file.
```
-(void)tabBar:(UITabBar *)tabBar didSelectedItem:(UITabBarItem *)item
```

## Required data for BioID Web Service
The required data (BWS instance name, client app id, client app secret and BCID of the user) is specified in the `CaptureConfiguration.m` file


### Request a trial instance 
On bwsportal.bioid.com request a [trial instance](https://bwsportal.bioid.com/register).
A free user registration is required. After you have access to the BioID Web Service (BWS) you can continue to create and configure your client app.


### Create and configure your client app on bwsportal.bioid.com
After you are logged in to the portal, select your client and go to the 'Configuration' section. 
The 'Client configuration' contains all information for accessing the BWS, as well as other information needed for the user BCIDs.

For the creation of BCIDs for users in your app the following information is needed:

- Storage e.g. `bws`
- Partition e.g. `12`
- UserID – this is a unique number you assign to the user, e.g. `4711`


The BCID with the example values from above is `bws.12.4711`.
Take a look at Web API endpoint for e.g. `https://bws.bioid.com`. In this case the BWS instance name is `bws`.

Click on the 'Web API keys' the add button. In the dialog window the app identifier and app secret is shown.

***Now you have all necessary data to call BWS!***

