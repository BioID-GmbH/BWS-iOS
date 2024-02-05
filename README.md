# BWS-iOS 

## BWS iOS CaptureViewController for app integration

The **BioID Web Service** (BWS) is a cloud-based online service providing a powerful multimodal biometric technology with liveness detection 
to application developers. But often developers have some trouble writing a user interface for collecting the data required to perform the biometric tasks, 
notably face images. Therefore we want to provide some sample code that might be used in iOS to interact with the BWS.

The **captureView** folder contains everything you typically need to run a biometric task from your iOS app. To see how to implement this source code into your app please take a look at [GUIDE](GUIDE.md). 

Complete sample for biometric enrollment and verification is provided in the **sample** folder.

Please also take a look at the [Developer Documentation][developer].

# Before you start developing a BioID app - you must have the following credentials
- You need a [BioID Account][bioidaccountregister] with a **confirmed** email address.
- After creating the BioID Account you can request a free [trial instance][trial] for the BioID Web Service (BWS).
- After the confirmation for access to a trial instance you can login to the [BWS Portal][bwsportal].
- The BWS Portal shows you the activity for your installation and allows you to configure your test client.
- After login to the BWS Portal configure your test client. In order to access this client, please do the steps below.
- Click on 'Show client keys' on your clients (the 'key' icon on the right). The dialog 'Classic keys' opens.
- Now create a new classic key (WEB API key) for your client implementation by clicking the '+' symbol.
- You will need the _AppId_ and _AppSecret_ for your client implementation. 
> :warning: _Please note that we only store a hash of the secret i.e the secret value cannot be reconstructed! So you should copy the value of the secret immediately!_


BioID offers sophisticated [face liveness detection][liveness] for distinguishing live persons from fraud attempts through photo/video replay attacks or 3D masks.

You can also try out the BioID [facial recognition app][bioid] with identity management using BioID Connect - available via [iTunes App Store][appstore].

[<img src="https://img.youtube.com/vi/e5lP2Fja3Ow/maxresdefault.jpg" width="50%">](https://youtu.be/e5lP2Fja3Ow)

[bioid]: https://www.bioid.com/facial-recognition-app/ "BioID Facial Recognition App"
[appstore]: https://apps.apple.com/us/app/bioid-facial-recognition-authenticator/id1054317153 "BioID iOS app"
[bioidaccountregister]: https://account.bioid.com/Account/Register "Register a BioID account" 
[trial]: https://bwsportal.bioid.com/register "Register for a trial instance"
[bwsportal]: https://bwsportal.bioid.com "BWS Portal"
[developer]: https://developer.bioid.com "Developer Documentation"
[liveness]: https://www.bioid.com/liveness-detection/ "liveness detection"
