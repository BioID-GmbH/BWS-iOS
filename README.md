# BWS-iOS 

## BWS iOS CaptureViewController for app integration

The **BioID Web Service** (BWS) is a cloud-based online service providing a powerful multimodal biometric technology with liveness detection 
to application developers. But often developers have some trouble writing a user interface for collecting the data required to perform the biometric tasks, 
notably face images. Therefore we want to provide some sample code that might be used in iOS to interact with the BWS.

The **captureView** folder contains everything you typically need to run a biometric task from your iOS app. To see how to implement this source code into your app please take a look at [GUIDE](GUIDE.md). 

### Example:
Complete sample for biometric enrollment and verification is provided in the **sample** folder.

To successfully run the sample iOS app, you need to have access to an existing BWS installation. If you don't have this access you can [register for a trial instance][trial].
For the complete documentation of the BWS API please visit the [Developer Reference][docs].

BioID offers sophisticated [face liveness detection][liveness] for distinguishing live persons from fraud attempts through photo/video replay attacks or 3D masks.

You can also try out the BioID [facial recognition app][bioid] with identity management using BioID Connect - available via [iTunes App Store][appstore].

[bioid]: https://www.bioid.com/facial-recognition-app "BioID Facial Recognition App"
[appstore]: https://apps.apple.com/us/app/bioid-facial-recognition-authenticator/id1054317153 "BioID iOS app"
[docs]: https://developer.bioid.com/bwsreference "BWS documentation"
[trial]: https://bwsportal.bioid.com/register "Register for a trial instance"
[liveness]: https://www.bioid.com/liveness-detection/ "liveness detection"
