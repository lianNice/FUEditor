varying vec3 N_frag,dPds_frag,dPdt_frag;
varying vec2 st_frag;
varying vec3 V_frag;

vec3 QuatTransformVector(vec4 Q,vec3 v){
	return v + 2.0*cross(Q.xyz, cross(Q.xyz,v) + Q.w*v);
}

float G1V(float dotNV, float k){
	return 1.0/(dotNV*(1.0-k)+k);
}
float selfDot(vec3 v){
	return v.x * v.x + v.y * v.y + v.z * v.z;
}

float sqr(float a){return a*a;}
vec3 sqr(vec3 a){return a*a;}
vec4 sqr(vec4 a){return vec4(sqr(a.rgb), a.a);}

float fresnel(float c){
	float g=sqrt(max(Fresnel_index*Fresnel_index-1.0+c*c,0.0));
	return 0.5*sqr((g-c)/(g+c))*(1.0+sqr(c*(g+c)-1.0)/sqr(c*(g-c)+1.0));
}

float LightingFuncWard_REF(vec3 N, vec3 V, vec3 L, float roughness, vec3 X, vec3 Y){
	float alpha = roughness*roughness;

	vec3 H = normalize(V+L);

	float dotNL = clamp(dot(N,L),0.0,1.0);
	float dotNV = clamp(dot(N,V),0.0,1.0);
	float dotNH = clamp(dot(N,H),0.0,1.0);
	float dotLH = clamp(dot(L,H),0.0,1.0);

	float F, D, vis;

	// D
	float dotHX = dot(H, X);
	float dotHY = dot(H, Y);
	float pi = 3.141592653;
	//float anisotropic = -10.0;
	//float aspect = sqrt(1.0 - anisotropic * 0.9);
	//float spreadX = max(0.001, sqr(roughness) / aspect) * 2;
	//float spreadY = max(0.001, sqr(roughness) * aspect) * 2;
	
	spreadX=clamp(1.0-spreadX/100.0, 0.01, 1.0);
	spreadX=spreadX*roughness;
	
	spreadY=clamp(1.0-spreadY/100.0, 0.01, 1.0);
	spreadY=spreadY*roughness;
	
	float exponent = -(sqr(dotHX/spreadY) + sqr(dotHY/spreadX)) / sqr(dotNH);
	D = 1.0 / (4.0 * pi * spreadX * spreadY * sqrt(dotNL * dotNV));
	D *= exp(exponent);
	
	// F
	F = fresnel(dotNL);

	// V
	vis = pow(dotNL * dotNV, 0.5);

	float specular = D * F * vis/(4.0*dotNL*dotNV);
	return sqrt(specular);
} 

vec3 sampleEnv(vec3 R0){
	vec3 R=normalize(R0);
	float phi;
	if(abs(R.x)<abs(R.z)){
		phi=(3.1415926*0.5-atan(abs(R.x/R.z)));
	}else{
		phi=atan(abs(R.z/R.x));
	}
	if(R.x<0.0){
		if(R.z<0.0){
			phi=-(3.1415926-phi);
		}else{
			phi=3.1415926-phi;
		}
	}else{
		if(R.z<0.0){
			phi=-phi;
		}else{ 
			phi=phi;
		}
	}
	phi=phi*(0.5/3.1415926);
	float theta=asin(clamp(R.y,-0.99,0.99))*(1.0/3.1415926)+0.5;
	phi=phi*envmap_fov+envmap_shift;
	theta=theta*envmap_fov;
	phi-=floor(phi);theta-=floor(theta);
	return sqr(texture2D(tex_light_probe,vec2(phi,theta)).xyz)*4.0;
}

vec4 shader_main(){
	vec3 N=-normalize(N_frag);
	vec3 N_pre=N;
	if (selfDot(dPds_frag) > 0.0 && selfDot(dPdt_frag) > 0.0 && normal_strength > 0.0){
		vec3 nmmp=normalize(texture2D(tex_normal,st_frag).xyz-vec3(0.5));
		N+=(normalize(-nmmp.x*normalize(dPds_frag)-nmmp.y*normalize(dPdt_frag)+nmmp.z*N)-N)*normal_strength;
		N=normalize(N);	
	}
	vec3 C_diff=vec3(0.0,0.0,0.0);
	float C_spec=0.0;
	vec3 V=-normalize(V_frag),L;
	float dotNV=dot(N,V);
	vec3 R=V-2.0*dotNV*N;
	if(dotNV<0.0){
		if(is_hair>0.5){
			N=-N;
			dotNV=-dotNV;
		}else{
			dotNV=0.0;
		}
	}
	
	// 旋转高光角度
	float specAngle, sinAngle;
	vec4 qua;
	vec3 X, Y;
	
	X = normalize(dPds_frag);
		
	specAngle = radians(angle)/4.0;
	sinAngle = sin(specAngle);
	qua = vec4(N_pre.x*sinAngle, N_pre.y*sinAngle, N_pre.z*sinAngle, cos(specAngle)); 
	X = QuatTransformVector(qua, X);
	
	Y = cross(N, X);
	
	L=-L0_dir;C_diff+=max(dot(N,L),0.0)*L0_color; C_spec+=LightingFuncWard_REF(N,V,L,roughness,X,Y);
	L=-L1_dir;C_diff+=max(dot(N,L),0.0)*L1_color; //C_spec+=LightingFuncGGX_REF(N,V,L,roughness,0.08);
	//L=-L2_dir;C_diff+=max(dot(N,L),0.0)*L2_color; C_spec+=LightingFuncGGX_REF(N,V,L,roughness,0.08);
	float smoothness=sqr(texture2D(tex_smoothness,st_frag).x)*has_tex_smoothness+(1.0-has_tex_smoothness);
	vec4 C_tex=sqr(texture2D(tex_albedo,st_frag));
	vec3 C_brdf=vec3(incandescence)+(C_diff*diffuse+vec3(ambient_color))*C_tex.xyz+vec3(specular_color*smoothness)*(C_spec);
	vec3 C_refl=sampleEnv(R);
	return vec4(sqrt(C_brdf+(C_refl-C_brdf)*(fresnel(dotNV)*reflectivity*smoothness)),C_tex.w);
}
