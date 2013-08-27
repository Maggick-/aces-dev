// 
// Output Device Transform to X'Y'Z'
// v0.2
//

// 
// Summary :
//  The output of this transform follows the encoding specified in SMPTE 
//  S428-1-2006. The gamut is a device-independent colorimetric encoding based  
//  on CIE XYZ. Therefore, output values are not limited to any physical 
//  device's actual color gamut that is determined by its color primaries.
// 
//  The assumed observer adapted white is D60, and the viewing environment is 
//  that of a dark theater. 
//
//  This transform shall be used for a device calibrated to match the Digital 
//  Cinema Reference Projector Specification outlined in SMPTE RP 431-2-2007.
//
// Assumed observer adapted white point:
//         CIE 1931 chromaticities:    x            y
//                                     0.32168      0.33767
//
// Viewing Environment:
//  Environment specified in SMPTE RP 431-2-2007
//

import "utilities";
import "utilities-aces";

/* ----- ODT Parameters ------ */
const Chromaticities RENDERING_PRI = 
{
  {0.73470, 0.26530},
  {0.00000, 1.00000},
  {0.12676, 0.03521},
  {0.32168, 0.33767}
};
const float XYZ_2_RENDERING_PRI_MAT[4][4] = XYZtoRGB(RENDERING_PRI,1.0);
const float OCES_PRI_2_XYZ_MAT[4][4] = RGBtoXYZ(ACES_PRI,1.0);
const float OCES_PRI_2_RENDERING_PRI_MAT[4][4] = mult_f44_f44( OCES_PRI_2_XYZ_MAT, XYZ_2_RENDERING_PRI_MAT);
const float RENDERING_PRI_2_XYZ_MAT[4][4] = RGBtoXYZ(RENDERING_PRI,1.0);

// ODT parameters related to black point compensation (BPC) and encoding
const float ODT_OCES_BP = 0.0001;
const float ODT_OCES_WP = 48.0;
const float OUT_BP = 0.0048;
const float OUT_WP = 48.0;

const float DISPGAMMA = 2.6; 
const unsigned int BITDEPTH = 12;
const unsigned int CV_BLACK = 0;
const unsigned int CV_WHITE = pow( 2, BITDEPTH) - 1;
const unsigned int MIN_CV = 0;
const unsigned int MAX_CV = pow( 2, BITDEPTH) - 1;

// Derived BPC and scale parameters
const float BPC = (ODT_OCES_BP * OUT_WP - ODT_OCES_WP * OUT_BP) / 
                  (ODT_OCES_BP - ODT_OCES_WP);
const float SCALE = (OUT_BP - OUT_WP) / (ODT_OCES_BP - ODT_OCES_WP);



void main 
(
  input varying float rIn, 
  input varying float gIn, 
  input varying float bIn, 
  input varying float aIn,
  output varying float rOut,
  output varying float gOut,
  output varying float bOut,
  output varying float aOut
)
{
  // Put input variables (OCES) into a 3-element vector
  float oces[3] = {rIn, gIn, bIn};

  // Convert from OCES to rendering primaries encoding
  float rgbPre[3] = mult_f3_f44( oces, OCES_PRI_2_RENDERING_PRI_MAT);

    // Apply the ODT tone scale independently to RGB 
    float rgbPost[3];
    rgbPost[0] = odt_tonescale_fwd( rgbPre[0]);
    rgbPost[1] = odt_tonescale_fwd( rgbPre[1]);
    rgbPost[2] = odt_tonescale_fwd( rgbPre[2]);

  // Restore the hue to the pre-tonescale value
  float rgbRestored[3] = restore_hue_dw3( rgbPre, rgbPost);

  // Apply Black Point Compensation
  float offset_scaled[3];
  offset_scaled[0] = (SCALE * rgbRestored[0]) + BPC;
  offset_scaled[1] = (SCALE * rgbRestored[1]) + BPC;
  offset_scaled[2] = (SCALE * rgbRestored[2]) + BPC;    

  // Luminance to code value conversion. Scales the luminance white point, 
  // OUT_WP, to be CV 1.0 and OUT_BP to CV 0.0.
  float linearCV[3];
  linearCV[0] = (offset_scaled[0] - OUT_BP) / (OUT_WP - OUT_BP);
  linearCV[1] = (offset_scaled[1] - OUT_BP) / (OUT_WP - OUT_BP);
  linearCV[2] = (offset_scaled[2] - OUT_BP) / (OUT_WP - OUT_BP);
  
  // Convert rendering primaries RGB to XYZ
  float XYZ[3] = mult_f3_f44( linearCV, RENDERING_PRI_2_XYZ_MAT);
  
  // Clamp to 0. 
  // There should not be any negative values but will clip just to ensure no 
  // math errors occur with the gamma function in the encoding function.
  XYZ = clamp_f3( XYZ, 0., HALF_POS_INF);

  // DCDM Color Encoding
  float cctf[3];
  cctf[0] = CV_WHITE * pow( 48./52.37 * XYZ[0], 1./DISPGAMMA);
  cctf[1] = CV_WHITE * pow( 48./52.37 * XYZ[1], 1./DISPGAMMA);
  cctf[2] = CV_WHITE * pow( 48./52.37 * XYZ[2], 1./DISPGAMMA);
    
  float outputCV[3] = clamp_f3( cctf, MIN_CV, MAX_CV);

  /*--- Cast outputCV to rOut, gOut, bOut ---*/
  // **NOTE**: The scaling step below is required when using ctlrender to 
  // process the images. This is because when ctlrender sees a floating-point 
  // file as the input and an integral file format as the output, it assumes 
  // that values out the end of the transform will be floating point, and so 
  // multiplies the output values by (2^outputBitDepth)-1. Therefore, although 
  // the values of outputCV are the correct integer values, they must be scaled 
  // into a 0-1 range on output because ctlrender will scale them back up in the 
  // process of writing the integer file.
  // The ctlrender option -output_scale could be used for this, but currently 
  // this option does not appear to function correctly.
  rOut = outputCV[0] / MAX_CV;
  gOut = outputCV[1] / MAX_CV;
  bOut = outputCV[2] / MAX_CV;
  aOut = aIn;
}